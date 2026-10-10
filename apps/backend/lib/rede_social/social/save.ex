defmodule RedeSocial.Social.Save do
  use Ecto.Schema

  @primary_key false
  schema "saves" do
    belongs_to :account, RedeSocial.Accounts.Account, type: :binary_id
    belongs_to :post, RedeSocial.Social.Post
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
