defmodule RedeSocial.Moderation do
  @moduledoc """
  Denúncias, remoções, recursos e avisos (seção 5 do plano).

  Quem decide é sempre uma pessoa da moderação. Toda remoção cita uma das
  regras públicas de `Rules`, o autor recebe um aviso com a regra e pode
  recorrer uma vez, e o recurso é julgado por outra pessoa da moderação,
  nunca por quem removeu. Cada decisão entra em `moderation_actions`, de
  onde saem os números da página de transparência.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Moderation.{Action, Appeal, Notice, Report, Rules}
  alias RedeSocial.Repo
  alias RedeSocial.Social.Post

  ## Denúncias

  @doc "Qualquer pessoa logada denuncia um post citando uma regra. Uma vez por post."
  def report(%Account{id: id}, %Post{author_id: id}, _rule), do: {:error, :own_post}

  def report(%Account{} = reporter, %Post{} = post, rule) do
    if Rules.reportable?(rule) do
      %Report{post_id: post.id, reporter_id: reporter.id, rule: rule}
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:post_id, :reporter_id])
      |> case do
        {:ok, _report} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_rule}
    end
  end

  @doc "Posts no ar com denúncias em aberto, dos mais denunciados para os menos."
  def queue do
    rows =
      from(r in Report,
        join: p in Post,
        on: p.id == r.post_id,
        where: is_nil(r.resolved_at) and is_nil(p.removed_at),
        group_by: [r.post_id, r.rule],
        select: {r.post_id, r.rule, count(r.id), type(min(r.inserted_at), :utc_datetime)}
      )
      |> Repo.all()

    post_ids = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    posts = Repo.all(from p in Post, where: p.id in ^post_ids, preload: :author)
    posts = Map.new(posts, &{&1.id, &1})

    rows
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {post_id, by_rule} ->
      reports =
        by_rule
        |> Enum.map(fn {_post, rule, count, _since} -> %{rule: rule, count: count} end)
        |> Enum.sort_by(&{-&1.count, &1.rule})

      since = by_rule |> Enum.map(&elem(&1, 3)) |> Enum.min(DateTime)

      %{
        post: Map.fetch!(posts, post_id),
        reports: reports,
        total: Enum.sum(Enum.map(reports, & &1.count)),
        since: since
      }
    end)
    |> Enum.sort_by(&{-&1.total, DateTime.to_unix(&1.since)})
  end

  ## Decisões

  @doc "Remove um post citando a regra. Fecha as denúncias e avisa o autor."
  def remove(%Account{moderator: true} = moderator, %Post{removed_at: nil} = post, rule) do
    if Rules.valid?(rule) do
      now = now()

      Multi.new()
      |> Multi.update(
        :post,
        Ecto.Changeset.change(post,
          removed_at: now,
          removal_rule: rule,
          removed_by_id: moderator.id
        )
      )
      |> Multi.update_all(:reports, open_reports(post),
        set: [resolved_at: now, resolution: "removed", resolved_by_id: moderator.id]
      )
      |> Multi.insert(:notice, %Notice{
        account_id: post.author_id,
        post_id: post.id,
        kind: "removed",
        rule: rule
      })
      |> Multi.insert(:action, action("removed", rule, post, moderator))
      |> transaction(:post)
    else
      {:error, :invalid_rule}
    end
  end

  def remove(%Account{moderator: true}, %Post{}, _rule), do: {:error, :already_removed}
  def remove(_account, _post, _rule), do: {:error, :not_moderator}

  @doc "Mantém o post no ar e fecha as denúncias em aberto."
  def keep(%Account{moderator: true} = moderator, %Post{} = post) do
    Multi.new()
    |> Multi.update_all(:reports, open_reports(post),
      set: [resolved_at: now(), resolution: "kept", resolved_by_id: moderator.id]
    )
    |> Multi.insert(:action, action("kept", nil, post, moderator))
    |> transaction(:action)
  end

  def keep(_account, _post), do: {:error, :not_moderator}

  defp open_reports(post) do
    from r in Report, where: r.post_id == ^post.id and is_nil(r.resolved_at)
  end

  ## Recursos

  @doc "O autor recorre de uma remoção, uma vez por remoção."
  def appeal(%Account{id: id}, %Post{author_id: id, removed_at: %DateTime{}} = post, text) do
    if appeal_status(post) == nil do
      %Appeal{post_id: post.id, author_id: id}
      |> Appeal.changeset(%{text: text || ""})
      |> Repo.insert()
    else
      {:error, :already_appealed}
    end
  end

  def appeal(%Account{id: id}, %Post{author_id: id}, _text), do: {:error, :not_removed}
  def appeal(_account, _post, _text), do: {:error, :not_found}

  @doc """
  Situação do recurso contra a remoção atual: nil (ninguém recorreu),
  "pending", "restore" ou "uphold".
  """
  def appeal_status(%Post{removed_at: nil}), do: nil

  def appeal_status(%Post{} = post) do
    Repo.one(
      from a in Appeal,
        where: a.post_id == ^post.id and a.inserted_at >= ^post.removed_at,
        order_by: [desc: a.inserted_at],
        limit: 1,
        select: coalesce(a.outcome, "pending")
    )
  end

  def pending_appeals do
    Repo.all(
      from a in Appeal,
        where: is_nil(a.decided_at),
        order_by: [asc: a.inserted_at],
        preload: [post: [:author, :removed_by]]
    )
  end

  def get_appeal(id), do: Repo.get(Appeal, id)

  @doc """
  Decide o recurso: "restore" devolve o post, "uphold" mantém a remoção.
  Quem removeu não pode julgar o próprio caso, e quem recorreu também não.

  A decisão só vale se o recurso ainda estiver em aberto no banco, para duas
  pessoas da moderação nunca decidirem o mesmo caso ao mesmo tempo.
  """
  def decide(%Account{moderator: true} = moderator, %Appeal{} = appeal, outcome)
      when outcome in ["restore", "uphold"] do
    post = Repo.get!(Post, appeal.post_id)

    if moderator.id in [post.removed_by_id, post.author_id] do
      {:error, :same_moderator}
    else
      kind = if outcome == "restore", do: "restored", else: "upheld"
      open = from a in Appeal, where: a.id == ^appeal.id and is_nil(a.decided_at)

      Multi.new()
      |> Multi.update_all(:appeal, open,
        set: [decided_at: now(), decided_by_id: moderator.id, outcome: outcome]
      )
      |> Multi.run(:still_open, fn _repo, %{appeal: {count, _}} ->
        if count == 1, do: {:ok, appeal.id}, else: {:error, :already_decided}
      end)
      |> then(fn multi ->
        if outcome == "restore",
          do: Multi.update(multi, :post, Ecto.Changeset.change(post, removed_at: nil)),
          else: multi
      end)
      |> Multi.insert(:notice, %Notice{
        account_id: post.author_id,
        post_id: post.id,
        kind: kind,
        rule: post.removal_rule
      })
      |> Multi.insert(:action, action(kind, post.removal_rule, post, moderator))
      |> transaction(:still_open)
      |> case do
        {:ok, id} -> {:ok, Repo.get!(Appeal, id)}
        error -> error
      end
    end
  end

  def decide(%Account{moderator: true}, _appeal, _outcome), do: {:error, :invalid_outcome}
  def decide(_account, _appeal, _outcome), do: {:error, :not_moderator}

  ## Avisos

  def notices(%Account{id: id}) do
    Repo.all(
      from n in Notice,
        where: n.account_id == ^id,
        order_by: [desc: n.inserted_at, desc: n.id],
        limit: 50,
        preload: [post: :author]
    )
  end

  def unread_count(%Account{id: id}) do
    Repo.aggregate(from(n in Notice, where: n.account_id == ^id and is_nil(n.read_at)), :count)
  end

  def mark_read(%Account{id: id}) do
    Repo.update_all(from(n in Notice, where: n.account_id == ^id and is_nil(n.read_at)),
      set: [read_at: now()]
    )

    :ok
  end

  ## Números públicos

  @doc "O que a página de transparência mostra sobre a moderação."
  def public_stats do
    counts =
      Repo.all(
        from a in Action, group_by: [a.action, a.rule], select: {a.action, a.rule, count(a.id)}
      )

    total = fn action ->
      counts |> Enum.filter(&(elem(&1, 0) == action)) |> Enum.map(&elem(&1, 2)) |> Enum.sum()
    end

    %{
      removals_by_rule: for({"removed", rule, count} <- counts, into: %{}, do: {rule, count}),
      kept: total.("kept"),
      appeals: %{
        restored: total.("restored"),
        upheld: total.("upheld"),
        pending: Repo.aggregate(from(a in Appeal, where: is_nil(a.decided_at)), :count)
      }
    }
  end

  @doc "Só para os dados de exemplo e para a entidade gestora, com duas pessoas."
  def grant_moderator(%Account{} = account) do
    account |> Ecto.Changeset.change(moderator: true) |> Repo.update()
  end

  defp action(kind, rule, post, moderator) do
    %Action{action: kind, rule: rule, post_id: post.id, moderator_id: moderator.id}
  end

  defp transaction(multi, key) do
    case Repo.transaction(multi) do
      {:ok, changes} -> {:ok, Map.fetch!(changes, key)}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
