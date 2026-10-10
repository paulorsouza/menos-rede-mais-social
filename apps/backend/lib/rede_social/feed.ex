defmodule RedeSocial.Feed do
  @moduledoc """
  Monta o feed de uma pessoa.

  Quem decide a ordem é o motor em Rust (services/feed-engine), com os
  parâmetros públicos de params/feed.toml. Este módulo só junta os candidatos
  e as ligações do grafo (quem curtiu e assistiu o quê), traduz os ids para o
  motor e devolve os posts com o motivo de cada um.
  """

  alias RedeSocial.{Engine, GraphCommitments, Social}
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

        {:ok,
         %{
           mode: mode,
           entries: entries,
           engine: engine_info(response),
           input: request,
           output: items,
           receipt: response["receipt"],
           index: index
         }}

      {:error, _reason} ->
        {:ok,
         %{mode: mode, entries: fallback(posts, follows, stats), engine: %{status: "offline"}}}
    end
  end

  @doc """
  A conta do feed, para quem quiser conferir: a entrada exata que foi para o
  motor, a saída e o recibo assinado. Os ids de conta viram números só deste
  pedido, então o arquivo não revela quem curtiu o quê.
  """
  def account(%Account{} = viewer, mode, kinds) do
    with {:ok, %{receipt: %{} = receipt} = feed} <- build(viewer, mode, kinds),
         {:ok, engine} <- Engine.transparency() do
      {:ok,
       %{
         sobre:
           "Conta do seu feed na -rede+social. Para conferir, rode o verificador aberto " <>
             "(services/verificador) com este arquivo e o params/feed.toml da versão indicada.",
         entrada: feed.input,
         saida: feed.output,
         recibo: receipt,
         chave_recibos: engine["receipt_public_key"]
       }
       |> Map.merge(data_proofs(viewer, feed))}
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  # As provas de que cada ligação usada no feed estava no último retrato do
  # grafo, cuja raiz está no registro público. Os ids continuam sendo os
  # números deste pedido; a tabela de pseudônimos liga cada número ao
  # pseudônimo do retrato, sem revelar a conta.
  defp data_proofs(viewer, feed) do
    case GraphCommitments.latest() do
      nil ->
        %{}

      snapshot ->
        by_number = Map.new(feed.index, fn {account_id, number} -> {number, account_id} end)

        alias_of = fn number ->
          GraphCommitments.pseudonym(snapshot, Map.fetch!(by_number, number))
        end

        edge_texts =
          Enum.map(feed.input.edges, fn edge ->
            case edge.kind do
              "like" ->
                GraphCommitments.like_text(alias_of.(edge.user_id), edge.post_id, edge.at)

              "watch" ->
                GraphCommitments.watch_text(
                  alias_of.(edge.user_id),
                  edge.post_id,
                  edge.watched_ms,
                  edge.at
                )
            end
          end)

        viewer_number = feed.input.viewer.id
        since = Social.following_since(viewer)

        follows =
          for number <- feed.input.viewer.follows do
            {number, Map.fetch!(since, Map.fetch!(by_number, number))}
          end

        follow_texts =
          for {number, at} <- follows,
              do: GraphCommitments.follow_text(alias_of.(viewer_number), alias_of.(number), at)

        {edge_proofs, follow_proofs} =
          snapshot
          |> GraphCommitments.proofs(edge_texts ++ follow_texts)
          |> Enum.split(length(edge_texts))

        %{
          retrato: %{
            id: snapshot.id,
            raiz: hex(snapshot.root),
            tamanho: snapshot.size,
            em: snapshot.taken_at,
            posicao_no_registro: snapshot.registro_position
          },
          pseudonimos:
            Map.new(feed.index, fn {_account, number} -> {number, alias_of.(number)} end),
          provas: %{
            ligacoes:
              for {proof, item} <- Enum.with_index(edge_proofs), proof != nil do
                %{item: item, folha: proof.position, caminho: Enum.map(proof.proof, &hex/1)}
              end,
            seguindo:
              for {proof, {number, at}} <- Enum.zip(follow_proofs, follows), proof != nil do
                %{
                  seguido: number,
                  desde: at,
                  folha: proof.position,
                  caminho: Enum.map(proof.proof, &hex/1)
                }
              end
          },
          recentes: %{
            ligacoes: for({nil, item} <- Enum.with_index(edge_proofs), do: item),
            seguindo:
              for {nil, {number, at}} <- Enum.zip(follow_proofs, follows) do
                %{seguido: number, desde: at}
              end
          }
        }
    end
  end

  defp hex(binary), do: Base.encode16(binary, case: :lower)

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
