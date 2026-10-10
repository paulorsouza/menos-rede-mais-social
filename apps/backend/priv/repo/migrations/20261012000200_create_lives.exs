defmodule RedeSocial.Repo.Migrations.CreateLives do
  use Ecto.Migration

  def change do
    # Cada live tem um post (kind "live") e uma chave de transmissão. Só o
    # hash da chave fica guardado.
    create table(:lives, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, on_delete: :delete_all), null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :key_hash, :binary, null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:lives, [:post_id])
    create index(:lives, [:status])
  end
end
