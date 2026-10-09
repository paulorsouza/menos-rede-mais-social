defmodule RedeSocial.Ads.Impression do
  @moduledoc """
  Um anúncio exibido nos shorts e como a receita dele foi dividida entre os
  criadores dos shorts assistidos antes.
  """
  use Ecto.Schema

  schema "ad_impressions" do
    belongs_to :campaign, RedeSocial.Ads.Campaign
    belongs_to :viewer, RedeSocial.Accounts.Account, type: :binary_id
    field :revenue_cents, :integer
    # id do criador => centavos recebidos.
    field :splits, :map, default: %{}
    # Um item por short: post, criador, tempo assistido e se tinha anúncio ligado.
    field :breakdown, {:array, :map}, default: []

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
