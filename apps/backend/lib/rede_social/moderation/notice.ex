defmodule RedeSocial.Moderation.Notice do
  @moduledoc """
  Aviso para o autor: o post saiu (com a regra), voltou ou continua fora
  depois do recurso.
  """
  use Ecto.Schema

  schema "notices" do
    belongs_to :account, RedeSocial.Accounts.Account, type: :binary_id
    belongs_to :post, RedeSocial.Social.Post
    field :kind, :string
    field :rule, :integer
    field :read_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
