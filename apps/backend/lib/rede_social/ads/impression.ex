defmodule RedeSocial.Ads.Impression do
  @moduledoc """
  Um anúncio exibido nos shorts e como a receita dele foi dividida entre os
  criadores dos shorts assistidos antes.
  """
  use Ecto.Schema

  schema "ad_impressions" do
    belongs_to :campaign, RedeSocial.Ads.Campaign
    belongs_to :viewer, RedeSocial.Accounts.Account, type: :binary_id
    # O anúncio que a rede mostrou. Cada um conta uma vez.
    belongs_to :slot, RedeSocial.Ads.AdSlot
    # Conta básica vê o anúncio, mas a parte dos criadores fica com o fundo.
    field :viewer_verified, :boolean, default: false
    field :revenue_cents, :integer
    # A parte que ficou com o fundo de infraestrutura.
    field :fund_cents, :integer, default: 0
    field :viewer_region, :string
    # id do criador => centavos recebidos.
    field :splits, :map, default: %{}
    # Um item por short: post, criador, tempo assistido e se tinha anúncio ligado.
    field :breakdown, {:array, :map}, default: []

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
