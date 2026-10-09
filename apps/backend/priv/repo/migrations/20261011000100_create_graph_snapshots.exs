defmodule RedeSocial.Repo.Migrations.CreateGraphSnapshots do
  use Ecto.Migration

  def change do
    # Retratos do grafo (curtidas, views e seguidores). A raiz vai para o
    # registro público; o sal dos pseudônimos nunca sai do banco.
    create table(:graph_snapshots) do
      add :root, :binary, null: false
      add :salt, :binary, null: false
      add :size, :integer, null: false
      add :registro_position, :bigint
      add :taken_at, :utc_datetime, null: false
    end

    create table(:graph_snapshot_leaves, primary_key: false) do
      add :snapshot_id, references(:graph_snapshots, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :leaf_hash, :binary, null: false
    end

    create unique_index(:graph_snapshot_leaves, [:snapshot_id, :position])
  end
end
