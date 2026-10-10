defmodule RedeSocial.Lives.Live do
  @moduledoc "Uma transmissão ao vivo e o post que a mostra no feed."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "lives" do
    belongs_to :post, RedeSocial.Social.Post, type: :id
    belongs_to :account, RedeSocial.Accounts.Account
    # Só o hash da chave de transmissão fica guardado.
    field :key_hash, :binary
    field :status, Ecto.Enum, values: [:waiting, :live, :ended]
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @doc "O caminho da live no servidor de transmissão (infra/ao-vivo)."
  def path(%__MODULE__{id: id}), do: "ao-vivo/" <> id
end
