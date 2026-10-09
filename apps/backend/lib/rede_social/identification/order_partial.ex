defmodule RedeSocial.Identification.OrderPartial do
  @moduledoc "A parte de um guardião para um item de uma ordem, já conferida pelo motor."
  use Ecto.Schema

  schema "identification_partials" do
    belongs_to :order, RedeSocial.Identification.Order
    field :guardian, :integer
    field :item_key, :string
    field :partial, :map

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
