defmodule RedeSocial.Moderation.Action do
  @moduledoc """
  Uma decisão da moderação: "removed", "kept", "restored" ou "upheld". O
  registro só cresce, e é dele que saem os números públicos.
  """
  use Ecto.Schema

  schema "moderation_actions" do
    field :action, :string
    field :rule, :integer
    belongs_to :post, RedeSocial.Social.Post
    belongs_to :moderator, RedeSocial.Accounts.Account, type: :binary_id

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
