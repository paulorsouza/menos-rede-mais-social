defmodule RedeSocial.Identification do
  @moduledoc """
  Identificação por ordem judicial (seção 3 do plano).

  1. O setor jurídico da entidade gestora registra a ordem: qual conta, qual
     juízo e o número do processo, ou que ele é sigiloso.
  2. A rede gera o pedido para os guardiões: o CPF selado da conta e os
     registros de acesso dos últimos seis meses, também selados.
  3. Cada guardião confere a ordem por conta própria e, se concordar, manda a
     sua parte. O motor confere a prova de cada parte antes de aceitar.
  4. Com 3 dos 5 guardiões, a ordem pode ser aberta uma única vez. O CPF e os
     IPs aparecem para quem abriu e não ficam guardados em lugar nenhum.
  5. Toda abertura entra no registro público com a data e o juízo, sem nada
     que identifique a pessoa. Processo sigiloso aparece só na contagem.
  """

  import Ecto.Query

  alias RedeSocial.Accounts.{Account, CPF}
  alias RedeSocial.{AccessLogs, Accounts, Demo, Repo, Vault}
  alias RedeSocial.Identification.{Order, OrderPartial}

  @guardians 1..5

  ## Ordens

  def create_order(%Account{legal_officer: true} = officer, nickname, attrs) do
    case Accounts.get_by_nickname(nickname || "") do
      %Account{cpf_ciphertext: sealed} = account when is_binary(sealed) ->
        %Order{account_id: account.id, requested_by_id: officer.id}
        |> Order.changeset(attrs)
        |> Repo.insert()

      %Account{} ->
        {:error, :no_sealed_cpf}

      nil ->
        {:error, :not_found}
    end
  end

  def create_order(_account, _nickname, _attrs), do: {:error, :not_legal_officer}

  def list_orders do
    Repo.all(
      from o in Order,
        order_by: [desc: o.inserted_at, desc: o.id],
        preload: [:partials]
    )
  end

  def get_order(id), do: Order |> preload(:partials) |> Repo.get(id)

  @doc """
  O que precisa ser aberto: o CPF selado e os acessos selados da conta. Se a
  conta já foi apagada, sobram só os acessos, que a lei manda guardar.
  """
  def items(%Order{account_id: account_id}) do
    cpf =
      case Repo.get(Account, account_id) do
        %Account{cpf_ciphertext: sealed} when is_binary(sealed) ->
          [%{key: "cpf", context: Accounts.cpf_context(account_id), sealed: sealed, at: nil}]

        _ ->
          []
      end

    accesses =
      for log <- AccessLogs.for_account(account_id) do
        %{
          key: "acesso-#{log.id}",
          context: AccessLogs.context(account_id, log.inserted_at),
          sealed: log.sealed,
          at: log.inserted_at
        }
      end

    cpf ++ accesses
  end

  @doc "O arquivo que vai para os guardiões, no formato da linha de comando `cofre`."
  def package(%Order{} = order) do
    %{
      order_id: order.id,
      items:
        for item <- items(order) do
          %{key: item.key, context: item.context, sealed: Base.encode64(item.sealed)}
        end
    }
  end

  @doc "Guardiões que já mandaram partes para todos os itens da ordem."
  def ready_guardians(%Order{} = order) do
    keys = order |> items() |> MapSet.new(& &1.key)

    Enum.filter(@guardians, fn guardian ->
      given =
        order.partials
        |> Enum.filter(&(&1.guardian == guardian))
        |> MapSet.new(& &1.item_key)

      MapSet.subset?(keys, given)
    end)
  end

  ## Partes dos guardiões

  @doc """
  Recebe as partes de um guardião, uma por item, no formato
  `%{"cpf" => %{"index" => 2, "point" => ..., ...}}`. Cada parte é conferida
  pelo motor antes de ser guardada.
  """
  def submit(%Order{status: "collecting"} = order, guardian, partials_by_key)
      when guardian in @guardians and is_map(partials_by_key) do
    items = items(order)

    checked =
      Enum.map(items, fn item ->
        partial = Map.get(partials_by_key, item.key)

        cond do
          not is_map(partial) -> {:error, {:missing_partial, item.key}}
          partial["index"] != guardian -> {:error, {:bad_partial, item.key}}
          not Vault.verify(item.sealed, partial) -> {:error, {:bad_partial, item.key}}
          true -> {:ok, item.key, partial}
        end
      end)

    case Enum.find(checked, &match?({:error, _}, &1)) do
      nil ->
        now = DateTime.truncate(DateTime.utc_now(), :second)

        rows =
          for {:ok, key, partial} <- checked do
            %{
              order_id: order.id,
              guardian: guardian,
              item_key: key,
              partial: partial,
              inserted_at: now
            }
          end

        Repo.insert_all(OrderPartial, rows,
          on_conflict: {:replace, [:partial, :inserted_at]},
          conflict_target: [:order_id, :guardian, :item_key]
        )

        {:ok, get_order(order.id)}

      error ->
        error
    end
  end

  def submit(%Order{status: "opened"}, _guardian, _partials), do: {:error, :already_opened}
  def submit(_order, _guardian, _partials), do: {:error, :invalid_guardian}

  @doc """
  Só na demonstração: o motor calcula a parte de um guardião com as fatias de
  teste, para mostrar o fluxo sem as cinco instituições na sala.
  """
  def simulate_guardian(%Order{} = order, guardian) do
    if Demo.enabled?() do
      partials =
        Map.new(items(order), fn item ->
          {:ok, partial} = Vault.demo_partial(guardian, item.sealed)
          {item.key, partial}
        end)

      submit(order, guardian, partials)
    else
      {:error, :not_found}
    end
  end

  ## Abertura

  @doc """
  Abre a ordem com as partes recebidas. Devolve o CPF e os acessos uma única
  vez; nada disso é guardado.
  """
  def open(%Account{legal_officer: true} = officer, %Order{status: "collecting"} = order) do
    by_key = Enum.group_by(order.partials, & &1.item_key, & &1.partial)

    opened =
      Enum.reduce_while(items(order), {:ok, []}, fn item, {:ok, acc} ->
        case Vault.open(item.sealed, item.context, Map.get(by_key, item.key, [])) do
          {:ok, text} -> {:cont, {:ok, [{item, text} | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with {:ok, opened} <- opened do
      order
      |> Ecto.Changeset.change(
        status: "opened",
        opened_at: DateTime.truncate(DateTime.utc_now(), :second),
        opened_by_id: officer.id
      )
      |> Repo.update!()

      opened = Enum.reverse(opened)

      {:ok,
       %{
         cpf:
           Enum.find_value(opened, fn {item, text} -> item.key == "cpf" && CPF.format(text) end),
         accesses: for({item, ip} <- opened, item.key != "cpf", do: %{at: item.at, ip: ip})
       }}
    end
  end

  def open(%Account{legal_officer: true}, %Order{}), do: {:error, :already_opened}
  def open(_account, _order), do: {:error, :not_legal_officer}

  ## Registro público

  @doc "O que a página de transparência mostra: nada que identifique a pessoa."
  def public_log do
    opened =
      Repo.all(
        from o in Order,
          where: o.status == "opened",
          order_by: [desc: o.opened_at],
          select: %{
            opened_at: o.opened_at,
            court: o.court,
            case_number: o.case_number,
            secret: o.secret_case
          }
      )

    %{
      requested: Repo.aggregate(Order, :count),
      opened: length(opened),
      secret: Enum.count(opened, & &1.secret),
      entries:
        for entry <- opened, not entry.secret do
          %{opened_at: entry.opened_at, court: entry.court, case_number: entry.case_number}
        end
    }
  end

  @doc "Só para os dados de exemplo e para a entidade gestora, com duas pessoas."
  def grant_legal_officer(%Account{} = account) do
    account |> Ecto.Changeset.change(legal_officer: true) |> Repo.update()
  end
end
