defmodule RedeSocial.Repo.Migrations.CreateMedia do
  use Ecto.Migration

  def change do
    # Envios em andamento (protocolo tus). O arquivo fica numa pasta de
    # trabalho até virar post ou vencer.
    create table(:uploads, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :length, :bigint, null: false
      add :filename, :string
      add :content_type, :string
      add :completed_at, :utc_datetime
      add :used_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:uploads, [:account_id])
    create index(:uploads, [:inserted_at])

    # Cada vídeo processado, com o que ele custou: bytes de cada degrau e
    # tempo de CPU da conversão. É daqui que sai o custo por hora de vídeo.
    create table(:media_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :status, :string, null: false
      add :source_path, :string
      add :source_bytes, :bigint
      add :width, :integer
      add :height, :integer
      add :duration_ms, :integer
      add :has_audio, :boolean, default: false, null: false
      add :renditions, {:array, :map}
      add :stored_bytes, :bigint
      add :cpu_ms, :bigint
      add :wall_ms, :bigint
      add :captions, :boolean, default: false, null: false
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    alter table(:posts) do
      add :media_asset_id, references(:media_assets, type: :binary_id, on_delete: :nilify_all)
      add :media_status, :string, default: "ready", null: false
      add :poster_path, :string
      add :captions_path, :string
      add :duration_ms, :integer
      add :width, :integer
      add :height, :integer
    end

    create index(:posts, [:media_asset_id])
  end
end
