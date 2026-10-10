defmodule RedeSocial.Payments.Leaf do
  @moduledoc "Uma linha de extrato na árvore do fechamento, já em hash."
  use Ecto.Schema

  @primary_key false
  schema "payout_leaves" do
    belongs_to :month, RedeSocial.Payments.Month
    field :position, :integer
    field :leaf_hash, :binary
  end
end
