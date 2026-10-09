defmodule RedeSocial.Feed do
  @moduledoc """
  Monta o feed de uma pessoa.

  Quem decide a ordem é o motor em Rust (services/feed-engine), com os
  parâmetros públicos de params/feed.toml. Este módulo só junta os candidatos
  e as ligações do grafo (quem curtiu e assistiu o quê), traduz os ids para o
  motor e devolve os posts com o motivo de cada um.
  """

  alias RedeSocial.{Engine, Social}
  alias RedeSocial.Accounts.Account

  @modes ~w(bubble outside_bubble mixed chronological public_ranking)
  @candidate_limit 300

  # Data e "em alta" não olham o grafo, então nem buscam as ligações.
  @graph_modes ~w(bubble outside_bubble mixed)

  def modes, do: @modes
  def valid_mode?(mode), do: mode in @modes

  def build(%Account{} = viewer, mode, kinds, now \\ DateTime.utc_now()) do
    posts = Social.candidates(viewer, kinds, @candidate_limit)
    stats = Social.stats(posts, viewer)
    follows = Social.following_ids(viewer)

    edges =
      if mode in @graph_modes,
        do: Social.graph_edges(viewer, Enum.map(posts, & &1.id)),
        else: []

    # O motor trabalha com ids numéricos. A tradução é feita a cada pedido, em
    # ordem fixa, para o mesmo pedido sempre gerar o mesmo resultado.
    index =
      ([viewer.id | follows] ++ Enum.map(posts, & &1.author_id) ++ Enum.map(edges, & &1.user_id))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.with_index(1)
      |> Map.new()

    request = %{
      mode: mode,
      viewer: %{
        id: Map.fetch!(index, viewer.id),
        follows: Enum.map(follows, &Map.fetch!(index, &1))
      },
      candidates: Enum.map(posts, &candidate(&1, index, stats)),
      edges: Enum.map(edges, &%{&1 | user_id: Map.fetch!(index, &1.user_id)}),
      now: DateTime.to_unix(now)
    }

    case Engine.rank(request) do
      {:ok, %{"items" => items} = response} ->
        by_id = Map.new(posts, &{&1.id, &1})

        entries =
          Enum.flat_map(items, fn %{"post_id" => id, "reasons" => reasons} ->
            case Map.fetch(by_id, id) do
              {:ok, post} -> [%{post: post, stats: Map.fetch!(stats, id), reasons: reasons}]
              :error -> []
            end
          end)

        {:ok, %{mode: mode, entries: entries, engine: engine_info(response)}}

      {:error, _reason} ->
        {:ok,
         %{mode: mode, entries: fallback(posts, follows, stats), engine: %{status: "offline"}}}
    end
  end

  defp candidate(post, index, stats) do
    post_stats = Map.fetch!(stats, post.id)

    %{
      post_id: post.id,
      author_id: Map.fetch!(index, post.author_id),
      created_at: DateTime.to_unix(post.inserted_at),
      likes: post_stats.likes,
      saves: post_stats.saves
    }
  end

  defp engine_info(response) do
    %{
      status: "ok",
      version: response["engine_version"],
      build: response["engine_build"],
      params_version: response["params_version"],
      params_sha256: response["params_sha256"]
    }
  end

  # Sem o motor, mostra só quem a pessoa segue, por data. Sem algoritmo nenhum.
  defp fallback(posts, follows, stats) do
    followed = MapSet.new(follows)

    for post <- posts, MapSet.member?(followed, post.author_id) do
      %{post: post, stats: Map.fetch!(stats, post.id), reasons: [%{"kind" => "you_follow"}]}
    end
  end
end
