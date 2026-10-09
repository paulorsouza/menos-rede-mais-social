defmodule RedeSocial.Ads.Campaign do
  @moduledoc """
  Uma campanha comprada por um anunciante. A nacional compra horas de
  exibição por dia para o país todo. A regional vale para uma cidade, custa
  menos e paga menos ao criador.
  """
  use Ecto.Schema

  schema "ad_campaigns" do
    field :advertiser, :string
    field :title, :string
    field :body, :string
    field :cta, :string
    field :color, :string
    field :scope, Ecto.Enum, values: [:national, :regional]
    field :region, :string
    field :hours_per_day, :integer
    field :cents_per_impression, :integer
    field :paid_cents, :integer
    field :starts_on, :date
    field :ends_on, :date

    timestamps(type: :utc_datetime)
  end
end
