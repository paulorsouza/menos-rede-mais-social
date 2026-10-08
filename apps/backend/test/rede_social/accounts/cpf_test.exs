defmodule RedeSocial.Accounts.CPFTest do
  use ExUnit.Case, async: true

  alias RedeSocial.Accounts.CPF

  # 123.456.789-09 tem dígitos verificadores corretos e é usado só em testes.
  @valid "12345678909"

  test "aceita CPF com ou sem pontuação" do
    assert CPF.normalize("123.456.789-09") == {:ok, @valid}
    assert CPF.normalize(@valid) == {:ok, @valid}
  end

  test "recusa dígito verificador errado, dígitos repetidos e tamanho errado" do
    assert CPF.normalize("123.456.789-00") == {:error, :invalid_cpf}
    assert CPF.normalize("111.111.111-11") == {:error, :invalid_cpf}
    assert CPF.normalize("1234567890") == {:error, :invalid_cpf}
    assert CPF.normalize("abc") == {:error, :invalid_cpf}
    assert CPF.normalize(nil) == {:error, :invalid_cpf}
  end

  test "a impressão digital é estável, depende da chave e não contém o número" do
    first = CPF.fingerprint(@valid, "chave-a")

    assert first == CPF.fingerprint(@valid, "chave-a")
    assert first != CPF.fingerprint(@valid, "chave-b")
    assert byte_size(first) == 32
    refute String.contains?(first, @valid)
  end
end
