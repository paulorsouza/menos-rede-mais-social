defmodule RedeSocial.Vault do
  @moduledoc """
  O cofre do CPF, visto do backend.

  Quem faz a criptografia é o motor em Rust (services/cofre). O backend só
  pede para selar um texto com a chave pública dos guardiões e, numa ordem
  judicial, leva as partes dos guardiões para o motor conferir e abrir. O
  backend nunca vê a fatia de guardião nenhuma.

  Nos testes, `RedeSocial.Vault.Fake` faz o papel do motor.
  """

  @callback seal(plaintext :: String.t(), context :: String.t()) ::
              {:ok, binary()} | {:error, term()}
  @callback verify(sealed :: binary(), partial :: map()) :: boolean()
  @callback open(sealed :: binary(), context :: String.t(), partials :: [map()]) ::
              {:ok, String.t()} | {:error, term()}
  @callback demo_partial(index :: pos_integer(), sealed :: binary(), context :: String.t()) ::
              {:ok, map()} | {:error, term()}

  def seal(plaintext, context), do: impl().seal(plaintext, context)
  def verify(sealed, partial), do: impl().verify(sealed, partial)
  def open(sealed, context, partials), do: impl().open(sealed, context, partials)
  def demo_partial(index, sealed, context), do: impl().demo_partial(index, sealed, context)

  defp impl, do: Application.get_env(:rede_social, :vault, RedeSocial.Vault.Engine)
end
