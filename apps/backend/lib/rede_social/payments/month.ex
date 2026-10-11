defmodule RedeSocial.Payments.Month do
  @moduledoc "Um mês fechado: a raiz das linhas de todos os extratos e os totais."
  use Ecto.Schema

  schema "payout_months" do
    field :month, :date
    # Chave dos pseudônimos de quem viu os anúncios. Nunca sai do banco.
    field :salt, :binary, redact: true
    field :root, :binary
    field :leaves_count, :integer
    field :registro_position, :integer
    field :params_sha256, :string
    field :revenue_cents, :integer
    field :creators_cents, :integer
    field :fund_cents, :integer
    # O bônus dos criadores pequenos do mês (params/ads.toml, band_difference).
    field :bonus_pool_cents, :integer, default: 0
    field :bonus_eligible_views, :integer, default: 0
    field :closed_at, :utc_datetime
  end
end
