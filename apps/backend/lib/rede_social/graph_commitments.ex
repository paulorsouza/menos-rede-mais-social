defmodule RedeSocial.GraphCommitments do
  @moduledoc """
  Compromisso dos dados do feed (seção 9 do plano).

  De tempos em tempos a rede tira um retrato de todas as ligações do grafo:
  curtidas, views (o maior tempo assistido de cada pessoa em cada vídeo) e
  quem segue quem. Cada ligação vira uma folha de uma árvore de Merkle, e só a
  raiz vai para o registro público. Depois disso, a rede não consegue mais
  inventar uma curtida "do passado" para justificar um feed: a conta do feed
  traz a prova de que cada ligação usada estava no retrato.

  Ninguém aparece pelo id no retrato. Cada conta vira um pseudônimo, feito
  com uma chave secreta daquele retrato (o sal, que nunca sai do banco), e o
  pseudônimo muda de um retrato para outro.

  O texto de cada folha é este, igual no verificador (services/verificador):

      like|<pseudônimo>|<post>|<quando, em segundos Unix>
      watch|<pseudônimo>|<post>|<milissegundos assistidos>|<quando>
      follow|<pseudônimo de quem segue>|<pseudônimo de quem é seguido>|<desde quando>

  As folhas ficam em ordem crescente de hash, então a posição de cada uma é
  sempre a mesma para o mesmo retrato.
  """

  import Ecto.Query

  alias RedeSocial.{Registro, Repo}
  alias RedeSocial.GraphCommitments.{Leaf, Snapshot}
  alias RedeSocial.Registro.Merkle
  alias RedeSocial.Social.{Follow, Like, Post, View}

  @doc "Tira um retrato do grafo e publica a raiz no registro."
  def take_snapshot(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)
    salt = :crypto.strong_rand_bytes(32)
    leaves = salt |> leaf_texts() |> Enum.map(&Merkle.leaf_hash/1) |> Enum.sort()
    root = leaves |> Merkle.levels() |> Merkle.levels_root()

    Repo.transaction(fn ->
      snapshot =
        Repo.insert!(%Snapshot{root: root, salt: salt, size: length(leaves), taken_at: now})

      leaves
      |> Enum.with_index()
      |> Enum.map(fn {leaf, position} ->
        %{snapshot_id: snapshot.id, position: position, leaf_hash: leaf}
      end)
      |> Enum.chunk_every(5_000)
      |> Enum.each(&Repo.insert_all(Leaf, &1))

      {:ok, entry} =
        Registro.append("raiz-dados", %{
          retrato: snapshot.id,
          raiz: Base.encode16(root, case: :lower),
          ligacoes: length(leaves),
          em: now
        })

      snapshot |> Ecto.Changeset.change(registro_position: entry.position) |> Repo.update!()
    end)
  end

  def latest, do: Repo.one(from s in Snapshot, order_by: [desc: s.id], limit: 1)

  @doc "Pseudônimo de uma conta num retrato: HMAC do id com o sal do retrato."
  def pseudonym(%Snapshot{salt: salt}, account_id), do: pseudonym(salt, account_id)

  def pseudonym(salt, account_id) when is_binary(salt) do
    :crypto.mac(:hmac, :sha256, salt, account_id)
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
  end

  def like_text(pseudonym, post_id, at), do: "like|#{pseudonym}|#{post_id}|#{at}"

  def watch_text(pseudonym, post_id, watched_ms, at),
    do: "watch|#{pseudonym}|#{post_id}|#{watched_ms}|#{at}"

  def follow_text(follower, followed, at), do: "follow|#{follower}|#{followed}|#{at}"

  @doc """
  Provas de inclusão no retrato para estes textos de folha. Devolve, para
  cada texto, `%{position: ..., proof: [...]}` ou `nil` se a folha não estava
  no retrato (é mais nova que ele).
  """
  def proofs(%Snapshot{id: id}, texts) do
    leaves =
      Repo.all(
        from l in Leaf,
          where: l.snapshot_id == ^id,
          order_by: [asc: l.position],
          select: l.leaf_hash
      )

    positions = leaves |> Enum.with_index() |> Map.new()
    levels = Merkle.levels(leaves)

    Enum.map(texts, fn text ->
      case Map.fetch(positions, Merkle.leaf_hash(text)) do
        {:ok, position} -> %{position: position, proof: Merkle.levels_proof(levels, position)}
        :error -> nil
      end
    end)
  end

  # Todas as ligações do grafo, com as mesmas regras de Social.graph_edges/2:
  # ninguém se liga ao próprio post, e post removido não conta.
  defp leaf_texts(salt) do
    alias_for = fn id -> pseudonym(salt, id) end

    likes =
      Repo.all(
        from l in Like,
          join: p in Post,
          on: p.id == l.post_id,
          where: p.author_id != l.account_id and is_nil(p.removed_at),
          select: {l.account_id, l.post_id, l.inserted_at}
      )

    watches =
      Repo.all(
        from v in View,
          join: p in Post,
          on: p.id == v.post_id,
          where: p.author_id != v.viewer_id and is_nil(p.removed_at),
          group_by: [v.viewer_id, v.post_id],
          select:
            {v.viewer_id, v.post_id, max(v.watched_ms), type(max(v.inserted_at), :utc_datetime)}
      )

    follows = Repo.all(from f in Follow, select: {f.follower_id, f.followed_id, f.inserted_at})

    Enum.map(likes, fn {user, post, at} -> like_text(alias_for.(user), post, unix(at)) end) ++
      Enum.map(watches, fn {user, post, ms, at} ->
        watch_text(alias_for.(user), post, ms, unix(at))
      end) ++
      Enum.map(follows, fn {follower, followed, at} ->
        follow_text(alias_for.(follower), alias_for.(followed), unix(at))
      end)
  end

  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)

  defp unix(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
end
