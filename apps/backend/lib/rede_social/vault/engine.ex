defmodule RedeSocial.Vault.Engine do
  @moduledoc "O cofre pelo motor em Rust (rotas /vault/* do engine-server)."
  @behaviour RedeSocial.Vault

  alias RedeSocial.Engine

  @impl true
  def seal(plaintext, context) do
    with {:ok, %{"sealed" => sealed}} <- Engine.vault_seal(plaintext, context) do
      Base.decode64(sealed)
    end
  end

  @impl true
  def verify(sealed, partial) do
    match?({:ok, %{"valid" => true}}, Engine.vault_verify(Base.encode64(sealed), partial))
  end

  @impl true
  def open(sealed, context, partials) do
    case Engine.vault_open(Base.encode64(sealed), context, partials) do
      {:ok, %{"plaintext" => plaintext}} -> {:ok, plaintext}
      {:error, {:status, 422, _body}} -> {:error, :not_enough_guardians}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def demo_partial(index, sealed), do: Engine.vault_demo_partial(index, Base.encode64(sealed))
end
