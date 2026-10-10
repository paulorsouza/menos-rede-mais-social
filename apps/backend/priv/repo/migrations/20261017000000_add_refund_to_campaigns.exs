defmodule RedeSocial.Repo.Migrations.AddRefundToCampaigns do
  use Ecto.Migration

  def change do
    # Quando a campanha acaba, o que não foi entregue volta ao anunciante por
    # PIX, na conta de onde veio o pagamento (devolução do PIX recebido).
    alter table(:ad_campaigns) do
      add :delivered, :bigint
      add :refunded_cents, :bigint
      add :refund_e2e_id, :string
      add :ended_at, :utc_datetime
    end
  end
end
