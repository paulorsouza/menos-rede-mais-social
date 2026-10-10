defmodule RedeSocial.Payments.PixKey do
  @moduledoc "A chave PIX do criador, conferida como sendo do próprio CPF."
  use Ecto.Schema

  @primary_key {:account_id, :binary_id, autogenerate: false}
  schema "pix_keys" do
    field :key, :string, redact: true
    field :kind, Ecto.Enum, values: [:email, :phone, :random]
    # O que aparece na tela: m***@exemplo.com.
    field :hint, :string
    field :verified_at, :utc_datetime
  end
end
