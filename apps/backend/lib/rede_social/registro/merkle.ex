defmodule RedeSocial.Registro.Merkle do
  @moduledoc """
  A árvore de Merkle do registro público, no formato do Certificate
  Transparency (RFC 6962). É a mesma conta de `services/registro`, em Rust,
  que o verificador aberto usa; os testes dos dois lados conferem a mesma
  raiz de referência.
  """

  def leaf_hash(data), do: :crypto.hash(:sha256, <<0>> <> data)
  def node_hash(left, right), do: :crypto.hash(:sha256, <<1>> <> left <> right)

  @doc "Raiz da árvore com estas folhas (já em hash)."
  def root([]), do: :crypto.hash(:sha256, "")
  def root([leaf]), do: leaf

  def root(leaves) do
    {left, right} = Enum.split(leaves, split(length(leaves)))
    node_hash(root(left), root(right))
  end

  @doc "Prova de que a folha `index` está na árvore."
  def inclusion_proof(leaves, _index) when length(leaves) <= 1, do: []

  def inclusion_proof(leaves, index) do
    k = split(length(leaves))
    {left, right} = Enum.split(leaves, k)

    if index < k,
      do: inclusion_proof(left, index) ++ [root(right)],
      else: inclusion_proof(right, index - k) ++ [root(left)]
  end

  @doc "Prova de que as primeiras `old_size` folhas são o começo da árvore."
  def consistency_proof(leaves, old_size) when old_size == 0 or old_size >= length(leaves),
    do: []

  def consistency_proof(leaves, old_size), do: subproof(old_size, leaves, true)

  defp subproof(m, leaves, complete) do
    n = length(leaves)

    cond do
      m == n and complete ->
        []

      m == n ->
        [root(leaves)]

      true ->
        k = split(n)
        {left, right} = Enum.split(leaves, k)

        if m <= k,
          do: subproof(m, left, complete) ++ [root(right)],
          else: subproof(m - k, right, false) ++ [root(left)]
    end
  end

  @doc """
  Os níveis da árvore, de baixo para cima, para tirar muitas provas sem
  recalcular tudo a cada uma. Num nível ímpar, o último nó sobe sem par, o
  que dá exatamente a mesma árvore do RFC 6962.
  """
  def levels(leaves), do: build_levels([List.to_tuple(leaves)])

  defp build_levels([level | _] = levels) when tuple_size(level) <= 1, do: Enum.reverse(levels)

  defp build_levels([level | _] = levels) do
    n = tuple_size(level)

    paired =
      for i <- 0..(div(n, 2) - 1)//1, do: node_hash(elem(level, 2 * i), elem(level, 2 * i + 1))

    next = if rem(n, 2) == 1, do: paired ++ [elem(level, n - 1)], else: paired
    build_levels([List.to_tuple(next) | levels])
  end

  def levels_root(levels) do
    case List.last(levels) do
      {} -> root([])
      top -> elem(top, 0)
    end
  end

  def levels_proof(levels, index) do
    levels
    |> Enum.drop(-1)
    |> Enum.reduce({[], index}, fn level, {proof, i} ->
      sibling = Bitwise.bxor(i, 1)
      proof = if sibling < tuple_size(level), do: [elem(level, sibling) | proof], else: proof
      {proof, div(i, 2)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # Maior potência de 2 menor que n.
  defp split(n), do: split(n, 1)
  defp split(n, k) when k * 2 < n, do: split(n, k * 2)
  defp split(_n, k), do: k
end
