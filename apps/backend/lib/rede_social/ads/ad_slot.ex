defmodule RedeSocial.Ads.AdSlot do
  @moduledoc """
  Um anúncio que a rede mostrou a alguém: qual campanha, para quem, quando e
  junto de quais posts. Exibição só conta se veio de um destes.
  """
  use Ecto.Schema

  schema "ad_slots" do
    belongs_to :viewer, RedeSocial.Accounts.Account, type: :binary_id
    belongs_to :campaign, RedeSocial.Ads.Campaign
    field :kind, Ecto.Enum, values: [:shorts, :video]
    field :post_ids, {:array, :integer}, default: []
    field :served_at, :utc_datetime
    field :used_at, :utc_datetime
  end
end
