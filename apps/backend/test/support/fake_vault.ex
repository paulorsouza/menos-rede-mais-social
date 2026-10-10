defmodule RedeSocial.Vault.Fake do
  @moduledoc """
  Cofre de mentira para os testes do backend. Não cifra nada: só imita as
  regras do motor (contexto certo e pelo menos 3 guardiões diferentes), para
  testar o fluxo sem depender do Rust. A criptografia de verdade é testada em
  services/cofre.
  """
  @behaviour RedeSocial.Vault

  @threshold 3

  @impl true
  def seal(plaintext, context), do: {:ok, "fake|" <> context <> "|" <> plaintext}

  @impl true
  def verify("fake|" <> _rest, %{"index" => index, "point" => "fake"}) when index in 1..5,
    do: true

  def verify(_sealed, _partial), do: false

  @impl true
  def open("fake|" <> rest, context, partials) do
    [sealed_context, plaintext] = String.split(rest, "|", parts: 2)
    guardians = partials |> Enum.map(& &1["index"]) |> Enum.uniq() |> length()

    cond do
      guardians < @threshold -> {:error, :not_enough_guardians}
      sealed_context != context -> {:error, :wrong_context}
      true -> {:ok, plaintext}
    end
  end

  @impl true
  def demo_partial(index, _sealed) do
    {:ok, %{"index" => index, "point" => "fake", "challenge" => "fake", "response" => "fake"}}
  end
end
