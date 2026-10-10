defmodule RedeSocial.Ads.Campaign do
  @moduledoc """
  Uma campanha comprada por um anunciante. A nacional compra horas de
  exibição por dia para o país todo. A regional vale para uma cidade, custa
  menos e paga menos ao criador.

  O caminho: em análise pela moderação, aprovada esperando o PIX, no ar
  (ativa) do primeiro ao último dia comprado e encerrada depois disso, com o
  que não foi entregue devolvido por PIX.
  """
  use Ecto.Schema

  schema "ad_campaigns" do
    belongs_to :advertiser_record, RedeSocial.Ads.Advertiser, foreign_key: :advertiser_id

    field :status, Ecto.Enum,
      values: [:in_review, :awaiting_payment, :active, :rejected, :ended],
      default: :active

    field :impressions_per_day, :integer
    field :price_cents, :integer
    field :rejection_rule, :integer
    belongs_to :reviewed_by, RedeSocial.Accounts.Account, type: :binary_id
    field :reviewed_at, :utc_datetime
    field :charge_txid, :string
    field :brcode, :string
    field :paid_at, :utc_datetime
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
    # Preenchidos no encerramento.
    field :delivered, :integer
    field :refunded_cents, :integer
    field :refund_e2e_id, :string
    field :ended_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
