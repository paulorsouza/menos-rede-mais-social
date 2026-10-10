defmodule RedeSocial.Accounts.CNPJ do
  @moduledoc """
  CNPJ de quem anuncia. Diferente do CPF, o CNPJ é público e fica em texto:
  a biblioteca de anúncios mostra qual empresa pagou cada campanha.
  """

  @first [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
  @second [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]

  @doc "Só os 14 dígitos, se os dígitos verificadores conferem."
  def normalize(cnpj) when is_binary(cnpj) do
    digits = String.replace(cnpj, ~r/\D/, "")

    if valid?(digits), do: {:ok, digits}, else: {:error, :invalid_cnpj}
  end

  def normalize(_cnpj), do: {:error, :invalid_cnpj}

  def format(<<a::binary-2, b::binary-3, c::binary-3, d::binary-4, e::binary-2>>),
    do: "#{a}.#{b}.#{c}/#{d}-#{e}"

  def format(other), do: other

  @doc "Um CNPJ válido e aleatório, para a demonstração e os testes."
  def generate_for_testing do
    base = for(_ <- 1..8, do: Enum.random(0..9)) ++ [0, 0, 0, 1]
    first = check_digit(base, @first)
    second = check_digit(base ++ [first], @second)
    Enum.map_join(base ++ [first, second], &Integer.to_string/1)
  end

  defp valid?(<<_::binary-14>> = digits) do
    numbers = digits |> String.graphemes() |> Enum.map(&String.to_integer/1)
    {base, [first, second]} = Enum.split(numbers, 12)

    length(Enum.uniq(numbers)) > 1 and check_digit(base, @first) == first and
      check_digit(base ++ [first], @second) == second
  end

  defp valid?(_digits), do: false

  defp check_digit(numbers, weights) do
    rest =
      numbers |> Enum.zip(weights) |> Enum.map(fn {n, w} -> n * w end) |> Enum.sum() |> rem(11)

    if rest < 2, do: 0, else: 11 - rest
  end
end
