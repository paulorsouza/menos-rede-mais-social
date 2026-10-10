defmodule RedeSocial.Social.View do
  use Ecto.Schema

  schema "views" do
    belongs_to :post, RedeSocial.Social.Post
    belongs_to :viewer, RedeSocial.Accounts.Account, type: :binary_id
    field :watched_ms, :integer
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
