defmodule RedeSocial.Repo.Migrations.CreateAdSlots do
  use Ecto.Migration

  def change do
    # Cada anúncio que a rede mostra a alguém. Só conta exibição de anúncio
    # que a rede mostrou de fato: o app não escolhe campanha nem shorts.
    create table(:ad_slots) do
      add :viewer_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :campaign_id, references(:ad_campaigns, on_delete: :delete_all), null: false
      # "shorts" (um anúncio depois de um bloco) ou "video" (nos pontos que o
      # criador marcou, nos vídeos daquele feed).
      add :kind, :string, null: false
      add :post_ids, {:array, :bigint}, null: false, default: []
      add :served_at, :utc_datetime, null: false
      # Anúncio dos shorts conta uma vez só.
      add :used_at, :utc_datetime
    end

    create index(:ad_slots, [:viewer_id, :served_at])

    alter table(:ad_impressions) do
      add :slot_id, references(:ad_slots, on_delete: :nilify_all)
      add :viewer_verified, :boolean, null: false, default: false
    end

    create unique_index(:ad_impressions, [:slot_id])

    alter table(:ad_views) do
      add :slot_id, references(:ad_slots, on_delete: :nilify_all)
    end

    # O mesmo anúncio, no mesmo ponto do mesmo vídeo, conta uma vez por exibição.
    create unique_index(:ad_views, [:slot_id, :post_id, :moment])
  end
end
