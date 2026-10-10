defmodule RedeSocial.Accounts.CPF do
  @moduledoc """
  Validação e impressão digital do CPF.

  A rede nunca guarda o CPF em texto. A impressão digital é um HMAC-SHA256 com
  uma chave secreta: com ela dá para saber se um CPF já tem conta, mas não dá
  para voltar do valor guardado para o número.
  """

  @doc """
  Tira pontos, traço e espaços e confere os dígitos verificadores.
  """
  def normalize(cpf) when is_binary(cpf) do
    digits = String.replace(cpf, ~r/[.\-\s]/, "")

    if valid_digits?(digits), do: {:ok, digits}, else: {:error, :invalid_cpf}
  end

  def normalize(_cpf), do: {:error, :invalid_cpf}

  @doc "123.456.789-09, a partir dos 11 dígitos."
  def format(<<a::binary-3, b::binary-3, c::binary-3, d::binary-2>>), do: "#{a}.#{b}.#{c}-#{d}"
  def format(other), do: other

  @doc """
  Impressão digital de um CPF já normalizado.
  """
  def fingerprint(normalized_cpf, key) do
    :crypto.mac(:hmac, :sha256, key, normalized_cpf)
  end

  @doc """
  Gera um CPF de teste com dígitos verificadores corretos, para o ambiente de
  demonstração e para os testes. Nunca é usado com dados de pessoas reais.
  """
  def generate_for_testing do
    base = for _ <- 1..9, do: :rand.uniform(10) - 1

    if length(Enum.uniq(base)) == 1 do
      generate_for_testing()
    else
      first = check_digit(base)
      second = check_digit(base ++ [first])
      Enum.map_join(base ++ [first, second], &Integer.to_string/1)
    end
  end

  defp valid_digits?(digits) do
    with true <- String.match?(digits, ~r/^\d{11}$/),
         numbers = digits |> String.graphemes() |> Enum.map(&String.to_integer/1),
         # CPFs com todos os dígitos iguais passam na conta, mas não existem.
         false <- length(Enum.uniq(numbers)) == 1 do
      {base, [first, second]} = Enum.split(numbers, 9)
      check_digit(base) == first and check_digit(base ++ [first]) == second
    else
      _ -> false
    end
  end

  # Soma ponderada com pesos que descem até 2. Resto 10 vira 0.
  defp check_digit(numbers) do
    weights = Enum.to_list((length(numbers) + 1)..2//-1)

    sum =
      numbers
      |> Enum.zip(weights)
      |> Enum.map(fn {number, weight} -> number * weight end)
      |> Enum.sum()

    case rem(sum * 10, 11) do
      10 -> 0
      digit -> digit
    end
  end
end
