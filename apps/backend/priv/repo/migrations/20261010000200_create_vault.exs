defmodule RedeSocial.Repo.Migrations.CreateVault do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # Setor jurídico da entidade gestora: registra ordens judiciais.
      add :legal_officer, :boolean, null: false, default: false
    end

    # Sem chave estrangeira de propósito: se a conta for apagada, a lei ainda
    # manda guardar os acessos até o fim dos seis meses.
    create table(:access_logs) do
      add :account_id, :binary_id, null: false
      add :sealed, :binary, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:access_logs, [:account_id, :inserted_at])
    create index(:access_logs, [:inserted_at])

    create table(:identification_orders) do
      add :account_id, :binary_id, null: false
      add :court, :string, null: false
      add :case_number, :string
      add :secret_case, :boolean, null: false, default: false
      add :status, :string, null: false, default: "collecting"
      add :opened_at, :utc_datetime
      add :requested_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :opened_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create table(:identification_partials) do
      add :order_id, references(:identification_orders, on_delete: :delete_all), null: false
      add :guardian, :integer, null: false
      add :item_key, :string, null: false
      add :partial, :map, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:identification_partials, [:order_id, :guardian, :item_key])
  end
end
