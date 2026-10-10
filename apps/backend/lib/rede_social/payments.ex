defmodule RedeSocial.Payments do
  @moduledoc """
  O dinheiro dos criadores: fechamento do mês, extratos e repasse por PIX.

  No primeiro dia de cada mês, a rede fecha o anterior. Para cada criador, o
  motor de anúncios (em Rust, com params/ads.toml) conta as views com anúncio
  que valem, aplica as faixas, soma a parte dele em cada anúncio dos shorts e
  devolve as linhas do extrato. As linhas de todos os criadores viram uma
  árvore de Merkle; a raiz vai para o registro público. Cada criador baixa o
  extrato com as provas e refaz a conta no verificador, sem confiar na rede.

  Quem viu um anúncio aparece no extrato só por um pseudônimo, feito com uma
  chave secreta daquele mês.

  O repasse vai por PIX para uma chave que o banco confirma ser do próprio
  criador: o diretório do PIX diz o CPF do dono da chave, e a rede compara
  pela impressão digital, sem guardar o número. A chave não pode ser o
  próprio CPF, justamente para o CPF não ficar guardado em texto.
  """

  import Ecto.Query

  require Logger

  alias Ecto.Multi
  alias RedeSocial.{Accounts, Engine, Registro, Repo}
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Ads.{AdView, Impression}
  alias RedeSocial.Payments.{Leaf, Month, Payout, Pix, PixKey, TransferWorker}
  alias RedeSocial.Registro.Merkle

  ## Chave PIX

  def pix_key(%Account{id: id}), do: Repo.get(PixKey, id)

  @doc """
  Cadastra a chave PIX do criador. Só vale chave que o banco confirma ser do
  próprio CPF da conta. Repasses que esperavam por uma chave saem na hora.
  """
  def register_pix_key(%Account{} = account, key) do
    with true <- Accounts.verified?(account) || {:error, :not_verified},
         {:ok, kind, key} <- normalize_key(key),
         {:ok, owner} <- lookup(key),
         true <- owner_is?(account, owner.document) || {:error, :pix_key_not_yours} do
      {:ok, pix_key} =
        Repo.insert(
          %PixKey{
            account_id: account.id,
            key: key,
            kind: kind,
            hint: hint(kind, key),
            verified_at: now()
          },
          on_conflict: {:replace, [:key, :kind, :hint, :verified_at]},
          conflict_target: :account_id
        )

      retry_waiting_payouts(account)
      {:ok, pix_key}
    end
  end

  defp lookup(key) do
    case Pix.lookup_key(key) do
      {:ok, owner} -> {:ok, owner}
      {:error, _} -> {:error, :pix_key_not_found}
    end
  end

  defp owner_is?(%Account{id: id}, document) do
    match?(%Account{id: ^id}, Accounts.get_by_cpf(document))
  end

  @doc "E-mail, celular (+55...) ou chave aleatória. CPF como chave não."
  def normalize_key(key) when is_binary(key) do
    key = String.trim(key)
    digits = String.replace(key, ~r/\D/, "")

    cond do
      key =~ ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/ ->
        {:ok, :email, String.downcase(key)}

      key =~ ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/ ->
        {:ok, :random, String.downcase(key)}

      match?({:ok, _}, Accounts.CPF.normalize(digits)) and not String.starts_with?(key, "+") ->
        {:error, :cpf_pix_key}

      byte_size(digits) in [12, 13] and String.starts_with?(digits, "55") ->
        {:ok, :phone, "+" <> digits}

      byte_size(digits) in [10, 11] ->
        {:ok, :phone, "+55" <> digits}

      true ->
        {:error, :invalid_pix_key}
    end
  end

  def normalize_key(_key), do: {:error, :invalid_pix_key}

  defp hint(:email, key) do
    [user, domain] = String.split(key, "@", parts: 2)
    String.first(user) <> "***@" <> domain
  end

  defp hint(:phone, key), do: "celular terminado em " <> String.slice(key, -4, 4)
  defp hint(:random, key), do: "chave aleatória terminada em " <> String.slice(key, -4, 4)

  ## Fechamento do mês

  @doc """
  Fecha um mês (`month` é o primeiro dia dele). Um mês só fecha uma vez.
  """
  def close_month(%Date{} = month, now \\ DateTime.utc_now()) do
    month = Date.beginning_of_month(month)

    if Repo.get_by(Month, month: month) do
      {:error, :already_closed}
    else
      do_close(month, DateTime.truncate(now, :second))
    end
  end

  defp do_close(month, now) do
    salt = :crypto.strong_rand_bytes(32)
    {from, to} = month_range(month)
    label = Calendar.strftime(month, "%Y-%m")

    video = video_views(from, to)
    shorts = shorts_impressions(from, to)
    carry = carried_from_previous(month)
    inputs = creator_months(label, salt, video, shorts, carry)

    with {:ok, %{"results" => results, "params_sha256" => params_sha}} <-
           Engine.close_month(Map.values(inputs)) do
      leaves =
        results
        |> Enum.flat_map(& &1["leaves"])
        |> Enum.map(&Merkle.leaf_hash/1)
        |> Enum.sort()

      root = leaves |> Merkle.levels() |> Merkle.levels_root()
      revenue = Enum.sum_by(video, & &1.revenue) + Enum.sum_by(shorts, & &1.revenue_cents)
      earned = Enum.sum_by(results, &(&1["video_cents"] + &1["shorts_cents"]))

      Multi.new()
      |> Multi.insert(:month, %Month{
        month: month,
        salt: salt,
        root: root,
        leaves_count: length(leaves),
        params_sha256: params_sha,
        revenue_cents: revenue,
        creators_cents: earned,
        fund_cents: revenue - earned,
        closed_at: now
      })
      |> Multi.run(:leaves, fn repo, %{month: closed} ->
        leaves
        |> Enum.with_index()
        |> Enum.map(fn {hash, position} ->
          %{month_id: closed.id, position: position, leaf_hash: hash}
        end)
        |> Enum.chunk_every(5_000)
        |> Enum.each(&repo.insert_all(Leaf, &1))

        {:ok, length(leaves)}
      end)
      |> Multi.run(:payouts, fn repo, %{month: closed} ->
        keys = Map.new(repo.all(PixKey), &{&1.account_id, &1})
        {:ok, Enum.map(results, &insert_payout(repo, closed, inputs, keys, &1, now))}
      end)
      |> Multi.run(:registro, fn _repo, %{month: closed} ->
        Registro.append("fechamento", %{
          mes: label,
          raiz: Base.encode16(root, case: :lower),
          linhas: length(leaves),
          criadores: length(results),
          receita_centavos: revenue,
          criadores_centavos: earned,
          fundo_centavos: revenue - earned,
          parametros_sha256: params_sha,
          em: closed.closed_at
        })
      end)
      |> Multi.run(:position, fn repo, %{month: closed, registro: entry} ->
        {:ok,
         closed |> Ecto.Changeset.change(registro_position: entry.position) |> repo.update!()}
      end)
      |> Multi.run(:transfers, fn _repo, %{payouts: payouts} ->
        jobs =
          for %Payout{status: :sending} = payout <- payouts,
              do: TransferWorker.new(%{payout_id: payout.id})

        {:ok, Oban.insert_all(jobs)}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{position: closed, payouts: payouts}} -> {:ok, closed, payouts}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, {:engine, reason}}
    end
  end

  defp insert_payout(repo, month, inputs, keys, result, now) do
    account_id = result["creator"]
    key = keys[account_id]

    status =
      cond do
        not result["payable"] -> :carried
        key == nil -> :no_key
        true -> :sending
      end

    repo.insert!(%Payout{
      month_id: month.id,
      account_id: account_id,
      # Gravado do jeito que foi para o motor, com chaves de texto.
      input: inputs |> Map.fetch!(account_id) |> Jason.encode!() |> Jason.decode!(),
      result: result,
      total_cents: result["total_cents"],
      payable: result["payable"],
      status: status,
      pix_key_hint: key && key.hint,
      inserted_at: now,
      updated_at: now
    })
  end

  # O mês de Brasília, como o dia do antifraude e da entrega dos anúncios.
  @brasilia_offset -3 * 3600

  defp month_range(month) do
    start = fn date ->
      date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.add(-@brasilia_offset, :second)
    end

    {start.(month), start.(Date.shift(month, month: 1))}
  end

  defp video_views(from, to) do
    Repo.all(
      from v in AdView,
        where: v.inserted_at >= ^from and v.inserted_at < ^to,
        order_by: [asc: v.id],
        select: %{
          id: v.id,
          creator: v.creator_id,
          viewer: v.viewer_id,
          post: v.post_id,
          campaign: v.campaign_id,
          regional: v.regional,
          verified: v.viewer_verified,
          revenue: v.revenue_cents,
          at: v.inserted_at
        }
    )
  end

  defp shorts_impressions(from, to) do
    Repo.all(
      from i in Impression,
        where: i.inserted_at >= ^from and i.inserted_at < ^to,
        order_by: [asc: i.id]
    )
  end

  # Quem ficou abaixo do mínimo no mês anterior leva o saldo para este.
  defp carried_from_previous(month) do
    previous = Date.shift(month, month: -1)

    Repo.all(
      from p in Payout,
        join: m in Month,
        on: m.id == p.month_id,
        where: m.month == ^previous and p.status == :carried and not is_nil(p.account_id),
        select: {p.account_id, p.total_cents}
    )
    |> Map.new()
  end

  defp creator_months(label, salt, video, shorts, carry) do
    # Quem apagou a conta continua sendo uma pessoa só em cada view, sem
    # virar a mesma pessoa de todas as outras contas apagadas.
    alias_for = fn
      %{viewer: nil, id: id} -> pseudonym(salt, "apagada-#{id}")
      %{viewer: viewer} -> pseudonym(salt, viewer)
    end

    by_creator =
      Enum.group_by(video, & &1.creator, fn view ->
        %{
          viewer: alias_for.(view),
          post: view.post,
          campaign: view.campaign,
          regional: view.regional,
          at: DateTime.to_unix(view.at),
          viewer_verified: view.verified
        }
      end)

    shorts_by_creator =
      shorts
      |> Enum.flat_map(fn impression ->
        block = %{
          id: impression.id,
          revenue_cents: impression.revenue_cents,
          at: DateTime.to_unix(impression.inserted_at),
          viewer_verified: impression.viewer_verified,
          views:
            Enum.map(impression.breakdown, fn item ->
              %{
                creator: item["author_id"],
                watched_ms: item["watched_ms"],
                monetized: item["monetized"]
              }
            end)
        }

        for item <- impression.breakdown,
            item["monetized"],
            uniq: true,
            do: {item["author_id"], block}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    # Quem apagou a conta não recebe: a parte dele fica com o fundo. Nos
    # blocos dos shorts ele continua, porque o rateio dos outros depende dele.
    creators =
      (Map.keys(by_creator) ++ Map.keys(shorts_by_creator) ++ Map.keys(carry))
      |> Enum.uniq()
      |> existing_accounts()

    Map.new(creators, fn creator ->
      {creator,
       %{
         month: label,
         creator: creator,
         carry_in_cents: Map.get(carry, creator, 0),
         video_views: Map.get(by_creator, creator, []),
         shorts: Map.get(shorts_by_creator, creator, [])
       }}
    end)
  end

  defp existing_accounts(ids) do
    Repo.all(from a in Account, where: a.id in ^ids, select: a.id)
  end

  @doc "Pseudônimo de quem viu: HMAC do id com a chave do mês."
  def pseudonym(salt, account_id) do
    :crypto.mac(:hmac, :sha256, salt, account_id)
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
  end

  ## Repasse

  @doc "Manda o PIX de um extrato. Chamado pela fila (TransferWorker)."
  def transfer(%Payout{status: :sending, account_id: nil} = payout) do
    # A conta foi apagada antes do repasse: não há para quem mandar.
    payout |> Ecto.Changeset.change(status: :failed, error: "conta apagada") |> Repo.update()
  end

  def transfer(%Payout{status: :sending} = payout) do
    case Repo.get(PixKey, payout.account_id) do
      nil ->
        payout |> Ecto.Changeset.change(status: :no_key) |> Repo.update()

      key ->
        case Pix.transfer(key.key, payout.total_cents, "repasse-#{payout.id}") do
          {:ok, e2e} ->
            payout
            |> Ecto.Changeset.change(
              status: :paid,
              pix_e2e_id: e2e,
              pix_key_hint: key.hint,
              paid_at: now(),
              error: nil
            )
            |> Repo.update()

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def transfer(%Payout{} = payout), do: {:ok, payout}

  def fail(%Payout{} = payout, reason) do
    payout |> Ecto.Changeset.change(status: :failed, error: inspect(reason)) |> Repo.update()
  end

  defp retry_waiting_payouts(%Account{id: id}) do
    waiting =
      Repo.all(from p in Payout, where: p.account_id == ^id and p.status in [:no_key, :failed])

    Enum.each(waiting, fn payout ->
      payout |> Ecto.Changeset.change(status: :sending, error: nil) |> Repo.update!()
      Oban.insert!(TransferWorker.new(%{payout_id: payout.id}))
    end)
  end

  ## Extratos

  def statements(%Account{id: id}) do
    Repo.all(
      from p in Payout,
        join: m in Month,
        on: m.id == p.month_id,
        where: p.account_id == ^id,
        order_by: [desc: m.month],
        select: %{payout: p, month: m}
    )
  end

  def statement(%Account{id: id}, label) do
    with {:ok, month} <- parse_month(label) do
      Repo.one(
        from p in Payout,
          join: m in Month,
          on: m.id == p.month_id,
          where: p.account_id == ^id and m.month == ^month,
          select: %{payout: p, month: m}
      )
    end
  end

  defp parse_month(<<year::binary-4, "-", month::binary-2>>) do
    case Date.from_iso8601("#{year}-#{month}-01") do
      {:ok, date} -> {:ok, date}
      _ -> nil
    end
  end

  defp parse_month(_label), do: nil

  @doc """
  O extrato para baixar e conferir no verificador: a entrada e o resultado do
  motor, e a prova de que cada linha está na árvore publicada.
  """
  def statement_file(%{payout: payout, month: month}) do
    hashes =
      Repo.all(
        from l in Leaf,
          where: l.month_id == ^month.id,
          order_by: [asc: l.position],
          select: l.leaf_hash
      )

    positions = hashes |> Enum.with_index() |> Map.new()
    levels = Merkle.levels(hashes)

    proofs =
      Enum.map(payout.result["leaves"], fn text ->
        position = Map.fetch!(positions, Merkle.leaf_hash(text))

        %{
          folha: position,
          caminho:
            Enum.map(Merkle.levels_proof(levels, position), &Base.encode16(&1, case: :lower))
        }
      end)

    %{
      sobre:
        "Extrato de um mês, para conferir com o verificador aberto: " <>
          "verificador pagamento extrato.json --parametros params/ads.toml --registro entradas.json",
      mes: Calendar.strftime(month.month, "%Y-%m"),
      criador: payout.account_id,
      parametros_sha256: month.params_sha256,
      entrada: payout.input,
      resultado: payout.result,
      fechamento: %{
        raiz: Base.encode16(month.root, case: :lower),
        folhas: month.leaves_count,
        registro: month.registro_position
      },
      provas: proofs,
      repasse: %{
        situacao: payout.status,
        chave: payout.pix_key_hint,
        id_pix: payout.pix_e2e_id,
        em: payout.paid_at
      }
    }
  end

  ## Contas abertas

  @doc "Por mês fechado: receita de anúncios, o que foi para os criadores e para o fundo."
  def open_accounts do
    Repo.all(
      from m in Month,
        order_by: [desc: m.month],
        limit: 12,
        select: %{
          month: m.month,
          revenue_cents: m.revenue_cents,
          creators_cents: m.creators_cents,
          fund_cents: m.fund_cents,
          root: m.root,
          registro_position: m.registro_position
        }
    )
    |> Enum.map(&Map.update!(&1, :root, fn root -> Base.encode16(root, case: :lower) end))
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
