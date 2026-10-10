defmodule RedeSocial.Social.Follow do
  use Ecto.Schema

  @primary_key false
  schema "follows" do
    belongs_to :follower, RedeSocial.Accounts.Account, type: :binary_id
    belongs_to :followed, RedeSocial.Accounts.Account, type: :binary_id
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
