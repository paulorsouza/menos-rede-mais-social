defmodule RedeSocial.RemovalRequests do
  @moduledoc """
  Pedidos de remoção vindos de fora da rede (regra pétrea 9 e seção 5 do
  plano). Só valem pelo canal formal: o setor jurídico registra quem pediu,
  a base legal e o post, e decide.

  - Pedido judicial é cumprido: o post sai citando a regra 9 (ordem
    judicial) e o autor é avisado como em qualquer remoção.
  - Pedido de outro órgão (ministério, partido, empresa) não tira nada do ar
    sozinho. Só é cumprido se o post quebra uma regra pública, e a remoção
    cita essa regra. Senão, é recusado com o motivo.

  Toda decisão entra no registro público, com quem pediu e a base legal (o
  número do processo só quando não é sigiloso), e todos os pedidos entram no
  relatório trimestral.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias RedeSocial.{Registro, Repo}
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Moderation.{Action, Notice, Report, Rules}
  alias RedeSocial.RemovalRequests.Request
  alias RedeSocial.Social.Post

  @judicial_rule 9

  def list do
    Repo.all(from r in Request, order_by: [desc: r.inserted_at, desc: r.id], preload: :post)
  end

  def get(id), do: Request |> Repo.get(id) |> Repo.preload(:post)

  @doc "O setor jurídico registra o pedido, apontando o post."
  def create(%Account{legal_officer: true} = officer, post_id, attrs) do
    case post_id && Repo.get(Post, post_id) do
      %Post{} = post ->
        %Request{post_id: post.id, requested_by_id: officer.id}
        |> Request.changeset(attrs)
        |> Repo.insert()

      nil ->
        {:error, :not_found}
    end
  end

  def create(_account, _post_id, _attrs), do: {:error, :not_legal_officer}

  @doc """
  Cumpre o pedido. Judicial cita a regra 9; de outro órgão, precisa citar a
  regra pública que o post quebrou.
  """
  def comply(officer, request, rule \\ nil)

  def comply(
        %Account{legal_officer: true} = officer,
        %Request{status: "recebido"} = request,
        rule
      ) do
    rule = if request.kind == "judicial", do: @judicial_rule, else: rule

    if request.kind != "judicial" and (rule == @judicial_rule or not Rules.valid?(rule)) do
      {:error, :invalid_rule}
    else
      decide(officer, request, "cumprido", [rule: rule], fn multi ->
        remove_post(multi, request, rule, officer)
      end)
    end
  end

  def comply(%Account{legal_officer: true}, %Request{}, _rule), do: {:error, :already_decided}
  def comply(_account, _request, _rule), do: {:error, :not_legal_officer}

  @doc "Recusa o pedido, com o motivo. Pedido judicial não se recusa aqui."
  def refuse(
        %Account{legal_officer: true} = officer,
        %Request{status: "recebido"} = request,
        reason
      ) do
    reason = reason |> to_string() |> String.trim()

    cond do
      request.kind == "judicial" -> {:error, :judicial_order}
      reason == "" -> {:error, :reason_required}
      true -> decide(officer, request, "recusado", [refusal_reason: reason], & &1)
    end
  end

  def refuse(%Account{legal_officer: true}, %Request{}, _reason), do: {:error, :already_decided}
  def refuse(_account, _request, _reason), do: {:error, :not_legal_officer}

  defp decide(officer, request, status, fields, extra) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    open = from r in Request, where: r.id == ^request.id and r.status == "recebido"

    Multi.new()
    |> Multi.update_all(:request, open,
      set: [status: status, decided_by_id: officer.id, decided_at: now] ++ fields
    )
    |> Multi.run(:still_open, fn _repo, %{request: {count, _}} ->
      if count == 1, do: {:ok, request.id}, else: {:error, :already_decided}
    end)
    |> extra.()
    |> Multi.run(:registro, fn _repo, _changes ->
      Registro.append("pedido-remocao", public_entry(request, status, fields, now))
    end)
    |> Multi.run(:position, fn repo, %{registro: entry} ->
      repo.update_all(from(r in Request, where: r.id == ^request.id),
        set: [registro_position: entry.position]
      )

      {:ok, entry.position}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> {:ok, get(request.id)}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  # O post sai como numa remoção da moderação: cita a regra, fecha as
  # denúncias e avisa o autor.
  defp remove_post(multi, %Request{post_id: nil}, _rule, _officer), do: multi

  defp remove_post(multi, request, rule, officer) do
    multi
    |> Multi.run(:post, fn repo, _changes ->
      case repo.get(Post, request.post_id) do
        %Post{removed_at: nil} = post ->
          post
          |> Ecto.Changeset.change(
            removed_at: DateTime.truncate(DateTime.utc_now(), :second),
            removal_rule: rule,
            removed_by_id: officer.id
          )
          |> repo.update()
          |> then(fn {:ok, post} -> {:ok, {:removed, post}} end)

        # Já tinha saído por outro motivo: o pedido conta, sem nova remoção.
        post ->
          {:ok, {:already_out, post}}
      end
    end)
    |> Multi.run(:effects, fn repo, %{post: {outcome, post}} ->
      if outcome == :removed do
        repo.update_all(
          from(r in Report, where: r.post_id == ^post.id and is_nil(r.resolved_at)),
          set: [resolved_at: post.removed_at, resolution: "removed", resolved_by_id: officer.id]
        )

        repo.insert!(%Notice{
          account_id: post.author_id,
          post_id: post.id,
          kind: "removed",
          rule: rule
        })

        repo.insert!(%Action{
          action: "removed",
          rule: rule,
          post_id: post.id,
          moderator_id: officer.id
        })
      end

      {:ok, post}
    end)
  end

  defp public_entry(request, status, fields, now) do
    %{
      tipo: request.kind,
      orgao: request.authority,
      base_legal: request.legal_basis,
      processo: if(request.secret_case, do: "sigiloso", else: request.case_number),
      decisao: status,
      regra: fields[:rule],
      em: now
    }
  end

  @doc "Os pedidos de um período, para o relatório trimestral."
  def summary(from, to) do
    requests =
      Repo.all(
        from r in Request,
          where: r.inserted_at >= ^from and r.inserted_at < ^to,
          select: %{
            kind: r.kind,
            status: r.status,
            authority: r.authority,
            legal_basis: r.legal_basis,
            secret: r.secret_case
          }
      )

    count = fn kind, status ->
      Enum.count(requests, &(&1.kind == kind and (status == nil or &1.status == status)))
    end

    %{
      judiciais: %{recebidos: count.("judicial", nil), cumpridos: count.("judicial", "cumprido")},
      outros_orgaos: %{
        recebidos: count.("outro", nil),
        cumpridos: count.("outro", "cumprido"),
        recusados: count.("outro", "recusado")
      },
      por_orgao_e_base_legal:
        requests
        |> Enum.reject(& &1.secret)
        |> Enum.frequencies_by(&"#{&1.authority} · #{&1.legal_basis}"),
      em_segredo_de_justica: Enum.count(requests, & &1.secret)
    }
  end
end
