defmodule RedeSocial.Uploads.Upload do
  @moduledoc "Um envio em andamento. Os bytes ficam num arquivo da pasta de trabalho."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "uploads" do
    belongs_to :account, RedeSocial.Accounts.Account
    field :length, :integer
    field :filename, :string
    field :content_type, :string
    field :completed_at, :utc_datetime
    field :used_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
