defmodule RedeSocial.Repo.Migrations.CreateAds do
  use Ecto.Migration

  def change do
    create table(:ad_campaigns) do
      add :advertiser, :string, null: false
      add :title, :string, null: false
      add :body, :string
      add :cta, :string
      add :color, :string
      # national ou regional. O regional tem cidade/UF e custa menos.
      add :scope, :string, null: false
      add :region, :string
      add :hours_per_day, :integer, null: false
      add :cents_per_impression, :integer, null: false
      add :paid_cents, :bigint, null: false, default: 0
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:ad_impressions) do
      add :campaign_id, references(:ad_campaigns, on_delete: :delete_all), null: false

      add :viewer_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :revenue_cents, :integer, null: false
      # Quanto cada criador recebeu deste anúncio, pelo motor de anúncios.
      add :splits, :map, null: false, default: %{}
      # Tempo assistido de cada short que veio antes do anúncio.
      add :breakdown, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ad_impressions, [:campaign_id])
  end
end
