defmodule RedeSocial.Social do
  @moduledoc """
  Posts, curtidas, salvamentos, seguidores e views, e as ligações do grafo
  que o motor de feed usa.
  """

  import Ecto.Query

  alias RedeSocial.{Accounts, Media, Repo}
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Social.{Follow, Like, MonthlyViews, Post, Save, View}

  # Abaixo disso a view não conta para o pagamento do criador (seção 6 do plano).
  @min_watch_ms 2_000

  ## Posts

  @doc """
  Publica um post. Só contas verificadas publicam, e só quem pode receber por
  anúncios (gov.br prata ou ouro) consegue ligar anúncios no próprio vídeo.

  A rede não guarda categoria, tema nem tag de post nenhum. O que decide quem
  vê o quê é o grafo de curtidas, views e seguidores.
  """
  def create_post(%Account{} = author, attrs, upload \\ nil) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

    if Accounts.verified?(author) do
      attrs =
        if Accounts.can_monetize?(author),
          do: attrs,
          else: Map.merge(attrs, %{"monetized" => false, "ad_markers" => []})

      with {:ok, media_path} <- Media.store(upload, parse_kind(attrs["kind"])),
           {:ok, post} <-
             %Post{author_id: author.id, media_path: media_path}
             |> Post.changeset(attrs)
             |> Repo.insert() do
        {:ok, Repo.preload(post, :author)}
      end
    else
      {:error, :not_verified}
    end
  end

  def get_post(id) do
    Post
    |> where([p], p.id == ^id and is_nil(p.removed_at))
    |> preload(:author)
    |> Repo.one()
  end

  @doc "O post, se quem está vendo pode ver. Ver visible_to/2."
  def get_post(id, viewer) do
    Post
    |> where([p], p.id == ^id and is_nil(p.removed_at))
    |> visible_to(viewer)
    |> preload(:author)
    |> Repo.one()
  end

  @doc """
  Perfil privado de menor de idade: os posts de um menor só aparecem para ele
  mesmo e para quem ele segue. Seguir de volta é o jeito de aprovar alguém,
  sem tela de pedidos. Vale em todo lugar onde post aparece: feed, perfil,
  "Em alta" e post avulso.
  """
  def visible_to(query, nil) do
    from p in query,
      join: a in assoc(p, :author),
      where: is_nil(a.age_band) or a.age_band != ^:minor
  end

  def visible_to(query, %Account{id: viewer_id}) do
    from p in query,
      join: a in assoc(p, :author),
      as: :visible_author,
      where:
        is_nil(a.age_band) or a.age_band != ^:minor or a.id == ^viewer_id or
          exists(
            from f in Follow,
              where:
                f.follower_id == parent_as(:visible_author).id and f.followed_id == ^viewer_id
          )
  end

  @doc "Se quem está vendo pode ver os posts desta conta."
  def can_see_posts?(%Account{} = author, viewer) do
    cond do
      not Accounts.minor?(author) -> true
      viewer == nil -> false
      viewer.id == author.id -> true
      true -> following?(author, viewer)
    end
  end

  @doc "O post mesmo que tenha sido removido. Só para a moderação e para o autor."
  def get_post_any(id), do: Post |> preload(:author) |> Repo.get(id)

  def list_author_posts(%Account{id: author_id}, viewer, limit \\ 60) do
    Post
    |> where([p], p.author_id == ^author_id and is_nil(p.removed_at))
    |> visible_to(viewer)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^limit)
    |> preload(:author)
    |> Repo.all()
  end

  @doc "Posts mais recentes dos tipos pedidos. São os candidatos que o motor vai ordenar."
  def candidates(viewer, kinds, limit) do
    Post
    |> where([p], p.kind in ^kinds and is_nil(p.removed_at))
    |> visible_to(viewer)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^limit)
    |> preload(:author)
    |> Repo.all()
  end

  def get_posts(ids) do
    Post
    |> where([p], p.id in ^ids and is_nil(p.removed_at))
    |> preload(:author)
    |> Repo.all()
  end

  def count_by_kind do
    Post
    |> where([p], is_nil(p.removed_at))
    |> group_by([p], p.kind)
    |> select([p], {p.kind, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  def count_removed do
    Repo.aggregate(from(p in Post, where: not is_nil(p.removed_at)), :count)
  end

  defp parse_kind(kind) when is_atom(kind), do: kind

  defp parse_kind(kind) do
    Enum.find(Post.kinds(), &(Atom.to_string(&1) == kind))
  end

  ## Curtidas, salvamentos e contagens

  @empty_stats %{likes: 0, saves: 0, views: 0, liked: false, saved: false}

  def empty_stats, do: @empty_stats

  @doc "Curtidas, salvamentos e views de cada post, e o que a pessoa já curtiu ou salvou."
  def stats(posts, viewer) do
    ids = Enum.map(posts, & &1.id)
    likes = count_by_post(Like, ids)
    saves = count_by_post(Save, ids)
    views = count_by_post(View, ids)
    liked = reacted_by(Like, ids, viewer)
    saved = reacted_by(Save, ids, viewer)

    Map.new(ids, fn id ->
      {id,
       %{
         likes: Map.get(likes, id, 0),
         saves: Map.get(saves, id, 0),
         views: Map.get(views, id, 0),
         liked: MapSet.member?(liked, id),
         saved: MapSet.member?(saved, id)
       }}
    end)
  end

  defp count_by_post(schema, ids) do
    from(row in schema,
      where: row.post_id in ^ids,
      group_by: row.post_id,
      select: {row.post_id, count(row.post_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp reacted_by(_schema, _ids, nil), do: MapSet.new()

  defp reacted_by(schema, ids, %Account{id: account_id}) do
    from(row in schema,
      where: row.post_id in ^ids and row.account_id == ^account_id,
      select: row.post_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Curte ou descurte. Cada curtida é uma ligação no grafo (ver graph_edges/2),
  então descurtir já tira a ligação, sem passo nenhum a mais.
  """
  def toggle_like(%Account{} = account, %Post{} = post), do: toggle(Like, account, post)

  def toggle_save(%Account{} = account, %Post{} = post), do: toggle(Save, account, post)

  defp toggle(schema, account, post) do
    query = from(row in schema, where: row.account_id == ^account.id and row.post_id == ^post.id)

    case Repo.delete_all(query) do
      {0, _} ->
        Repo.insert!(struct(schema, account_id: account.id, post_id: post.id),
          on_conflict: :nothing
        )

        {:ok, true}

      {_deleted, _} ->
        {:ok, false}
    end
  end

  ## Seguidores

  def toggle_follow(%Account{id: id}, %Account{id: id}), do: {:error, :self_follow}

  def toggle_follow(%Account{} = follower, %Account{} = followed) do
    query =
      from(f in Follow, where: f.follower_id == ^follower.id and f.followed_id == ^followed.id)

    case Repo.delete_all(query) do
      {0, _} ->
        Repo.insert!(%Follow{follower_id: follower.id, followed_id: followed.id},
          on_conflict: :nothing
        )

        {:ok, true}

      {_deleted, _} ->
        {:ok, false}
    end
  end

  def following_ids(%Account{id: id}) do
    Repo.all(from f in Follow, where: f.follower_id == ^id, select: f.followed_id)
  end

  def following?(nil, _account), do: false

  def following?(%Account{} = viewer, %Account{} = account) do
    Repo.exists?(
      from f in Follow, where: f.follower_id == ^viewer.id and f.followed_id == ^account.id
    )
  end

  def follow_counts(%Account{id: id}) do
    %{
      followers: Repo.aggregate(from(f in Follow, where: f.followed_id == ^id), :count),
      following: Repo.aggregate(from(f in Follow, where: f.follower_id == ^id), :count)
    }
  end

  ## Grafo

  # Teto de ligações por pedido ao motor. Ele ainda descarta o que passou da
  # janela de params/feed.toml.
  @edge_limit 5_000

  @doc """
  As ligações do grafo que o motor precisa para montar o feed de alguém:
  quem curtiu e quem assistiu a cada post.

  Vão duas partes. Tudo o que fizeram a própria pessoa e quem curtiu ou
  assistiu às mesmas coisas que ela, porque é daí que o motor descobre quem
  tem gosto parecido. E quem curtiu ou assistiu aos posts candidatos.

  Aqui só se conta o que aconteceu. Quanto cada ligação vale, quanto tempo de
  vídeo conta e quem vira vizinho de quem está em params/feed.toml, e quem
  aplica é o motor. Ninguém se liga ao próprio post.
  """
  def graph_edges(%Account{id: id}, candidate_ids) do
    people = Enum.uniq([id | people_on(posts_touched_by(id))])
    like_edges(people, candidate_ids) ++ watch_edges(people, candidate_ids)
  end

  defp posts_touched_by(id) do
    liked = Repo.all(from l in Like, where: l.account_id == ^id, select: l.post_id)

    watched =
      Repo.all(from v in View, where: v.viewer_id == ^id, distinct: true, select: v.post_id)

    Enum.uniq(liked ++ watched)
  end

  defp people_on(post_ids) do
    likers = Repo.all(from l in Like, where: l.post_id in ^post_ids, select: l.account_id)

    watchers =
      Repo.all(from v in View, where: v.post_id in ^post_ids, distinct: true, select: v.viewer_id)

    likers ++ watchers
  end

  defp like_edges(people, post_ids) do
    from(l in Like,
      join: p in Post,
      on: p.id == l.post_id,
      where:
        (l.account_id in ^people or l.post_id in ^post_ids) and p.author_id != l.account_id and
          is_nil(p.removed_at),
      order_by: [desc: l.inserted_at, asc: l.post_id],
      limit: @edge_limit,
      select: %{user_id: l.account_id, post_id: l.post_id, at: l.inserted_at}
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, %{kind: "like", at: unix(&1.at)}))
  end

  # Várias views da mesma pessoa no mesmo vídeo viram uma ligação só, com o
  # maior tempo assistido.
  defp watch_edges(people, post_ids) do
    from(v in View,
      join: p in Post,
      on: p.id == v.post_id,
      where:
        (v.viewer_id in ^people or v.post_id in ^post_ids) and p.author_id != v.viewer_id and
          is_nil(p.removed_at),
      group_by: [v.viewer_id, v.post_id],
      order_by: [desc: max(v.inserted_at), asc: v.post_id],
      limit: @edge_limit,
      select: %{
        user_id: v.viewer_id,
        post_id: v.post_id,
        at: max(v.inserted_at),
        watched_ms: max(v.watched_ms)
      }
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, %{kind: "watch", at: unix(&1.at)}))
  end

  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)

  defp unix(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  ## Views

  @doc """
  Registra que alguém assistiu a um vídeo ou short. Só conta para o pagamento
  quando a pessoa assistiu pelo menos 2 segundos e não é o próprio criador.
  """
  def record_view(%Account{} = viewer, %Post{} = post, watched_ms) do
    watched_ms = watched_ms |> max(0) |> min(3_600_000)

    Repo.insert!(%View{post_id: post.id, viewer_id: viewer.id, watched_ms: watched_ms})

    if watched_ms >= @min_watch_ms and viewer.id != post.author_id do
      add_monthly_views(post.author_id, current_month(), 1)
    end

    :ok
  end

  def monthly_views(%Account{id: id}, month \\ current_month()) do
    Repo.one(
      from m in MonthlyViews, where: m.account_id == ^id and m.month == ^month, select: m.views
    ) || 0
  end

  def add_monthly_views(account_id, month, views) do
    Repo.insert_all(MonthlyViews, [%{account_id: account_id, month: month, views: views}],
      on_conflict: [inc: [views: views]],
      conflict_target: [:account_id, :month]
    )
  end

  def current_month, do: Date.beginning_of_month(Date.utc_today())
end
