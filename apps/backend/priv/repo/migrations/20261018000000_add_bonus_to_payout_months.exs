defmodule RedeSocial.Repo.Migrations.AddBonusToPayoutMonths do
  use Ecto.Migration

  def change do
    # O bônus dos criadores pequenos: o que as faixas deixaram de pagar a quem
    # cresceu e a soma das views de quem ficou na primeira faixa.
    alter table(:payout_months) do
      add :bonus_pool_cents, :bigint, null: false, default: 0
      add :bonus_eligible_views, :bigint, null: false, default: 0
    end
  end
end
