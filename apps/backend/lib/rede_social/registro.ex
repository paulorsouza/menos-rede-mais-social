defmodule RedeSocial.Registro do
  @moduledoc """
  Registro público da rede (seção 9 do plano).

  Uma árvore de Merkle que só aceita acréscimos. Entram nela as versões do
  motor com o hash dos parâmetros, a chave que assina os recibos do feed, as
  raízes dos dados e as aberturas de ordem judicial. A rede assina o
  cabeçalho (tamanho e raiz) com Ed25519, e qualquer pessoa confere com o
  verificador aberto que uma entrada está na árvore e que a árvore de hoje é
  a de ontem com coisas a mais.

  O texto de cada entrada é publicado do jeito exato que virou folha:
  "tipo" e o JSON com as chaves em ordem alfabética, separados por uma quebra
  de linha. Quem quiser refaz o hash.
  """

  import Ecto.Query

  alias RedeSocial.Registro.{Entry, Merkle}
  alias RedeSocial.Repo

  # Trava para duas entradas nunca disputarem a mesma posição.
  @lock 7_734_001

  @doc "Acrescenta uma entrada. Não existe função para mudar ou apagar."
  def append(kind, payload) when is_binary(kind) and is_map(payload) do
    data = kind <> "\n" <> canonical_json(payload)

    Repo.transaction(fn ->
      lock()
      insert(kind, data)
    end)
  end

  @doc """
  Acrescenta só se a última entrada deste tipo não tiver o mesmo conteúdo. A
  comparação e a escrita acontecem sob a mesma trava, para duas checagens ao
  mesmo tempo não anotarem a mesma coisa duas vezes.
  """
  def append_if_changed(kind, payload) when is_binary(kind) and is_map(payload) do
    data = kind <> "\n" <> canonical_json(payload)

    Repo.transaction(fn ->
      lock()

      case last_of_kind(kind) do
        %Entry{data: ^data} -> :same
        _ -> insert(kind, data)
      end
    end)
  end

  defp lock, do: Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock])

  defp insert(kind, data) do
    Repo.insert!(%Entry{
      position: Repo.aggregate(Entry, :count),
      kind: kind,
      data: data,
      leaf_hash: Merkle.leaf_hash(data),
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
  end

  def size, do: Repo.aggregate(Entry, :count)

  def entries(from \\ 0, to \\ nil) do
    query = from e in Entry, where: e.position >= ^from, order_by: [asc: e.position]
    query = if to, do: where(query, [e], e.position < ^to), else: query
    Repo.all(query)
  end

  def latest(limit) do
    Repo.all(from e in Entry, order_by: [desc: e.position], limit: ^limit)
  end

  def last_of_kind(kind) do
    Repo.one(from e in Entry, where: e.kind == ^kind, order_by: [desc: e.position], limit: 1)
  end

  @doc "O cabeçalho atual, assinado."
  def head do
    leaves = leaves(nil)

    head = %{
      size: length(leaves),
      root: Merkle.root(leaves),
      timestamp: System.system_time(:second)
    }

    Map.merge(head, %{signature: sign(head), public_key: public_key()})
  end

  @doc "Prova de inclusão da entrada `index` na árvore com `size` entradas."
  def inclusion(index, size) do
    leaves = leaves(size)

    if index >= 0 and index < length(leaves) do
      {:ok,
       %{
         index: index,
         size: length(leaves),
         leaf_hash: Enum.at(leaves, index),
         root: Merkle.root(leaves),
         proof: Merkle.inclusion_proof(leaves, index)
       }}
    else
      {:error, :not_found}
    end
  end

  @doc "Prova de que a árvore com `from` entradas é o começo da árvore com `to`."
  def consistency(from, to) do
    leaves = leaves(to)

    if from >= 0 and from <= length(leaves) do
      {:ok,
       %{
         from: from,
         to: length(leaves),
         old_root: leaves |> Enum.take(from) |> Merkle.root(),
         new_root: Merkle.root(leaves),
         proof: Merkle.consistency_proof(leaves, from)
       }}
    else
      {:error, :not_found}
    end
  end

  @doc "O texto que a rede assina, igual ao de `services/registro`."
  def signed_message(%{size: size, root: root, timestamp: timestamp}) do
    "registro -rede+social v1\n#{size}\n#{Base.encode16(root, case: :lower)}\n#{timestamp}\n"
  end

  def public_key do
    {public, _private} = :crypto.generate_key(:eddsa, :ed25519, seed())
    public
  end

  defp sign(head) do
    {_public, private} = :crypto.generate_key(:eddsa, :ed25519, seed())
    :crypto.sign(:eddsa, :none, signed_message(head), [private, :ed25519])
  end

  defp seed do
    :rede_social
    |> Application.fetch_env!(:registro_signing_seed)
    |> Base.decode64!()
  end

  defp leaves(nil),
    do: Repo.all(from e in Entry, order_by: [asc: e.position], select: e.leaf_hash)

  defp leaves(size) do
    Repo.all(
      from e in Entry,
        where: e.position < ^size,
        order_by: [asc: e.position],
        select: e.leaf_hash
    )
  end

  @doc "JSON com as chaves em ordem alfabética, sem espaços: sempre o mesmo texto."
  def canonical_json(value), do: value |> ordered() |> Jason.encode!()

  defp ordered(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp ordered(%Date{} = value), do: Date.to_iso8601(value)

  defp ordered(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), ordered(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value
end
