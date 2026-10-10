defmodule RedeSocial.Ads.AdView do
  @moduledoc """
  Um anúncio que passou dentro de um vídeo. É a base do pagamento por faixas:
  no fechamento do mês, o motor conta quais destas views valem, pelas regras
  do antifraude.
  """
  use Ecto.Schema

  schema "ad_views" do
    belongs_to :campaign, RedeSocial.Ads.Campaign
    belongs_to :post, RedeSocial.Social.Post
    belongs_to :creator, RedeSocial.Accounts.Account, type: :binary_id
    belongs_to :viewer, RedeSocial.Accounts.Account, type: :binary_id
    field :viewer_region, :string
    field :viewer_verified, :boolean
    field :regional, :boolean
    field :moment, :string
    field :revenue_cents, :integer
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
