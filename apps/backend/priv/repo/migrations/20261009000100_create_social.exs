defmodule RedeSocial.Repo.Migrations.CreateSocial do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :author_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false

      add :kind, :string, null: false
      add :body, :text
      add :media_path, :string
      add :monetized, :boolean, null: false, default: false
      add :ad_markers, {:array, :string}, null: false, default: []
      add :removed_at, :utc_datetime
      add :removal_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:posts, [:author_id])
    create index(:posts, [:kind, :inserted_at])

    for table <- [:likes, :saves] do
      create table(table, primary_key: false) do
        add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
          null: false

        add :post_id, references(:posts, on_delete: :delete_all), null: false
        timestamps(type: :utc_datetime, updated_at: false)
      end

      create unique_index(table, [:account_id, :post_id])
      create index(table, [:post_id])
    end

    create table(:follows, primary_key: false) do
      add :follower_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :followed_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:follows, [:follower_id, :followed_id])
    create index(:follows, [:followed_id])

    create table(:views) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false

      add :viewer_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false

      add :watched_ms, :integer, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:views, [:post_id])
    create index(:views, [:viewer_id])

    # Total de views de cada criador no mês, usado para o pagamento por faixas.
    create table(:monthly_views, primary_key: false) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :month, :date, null: false
      add :views, :bigint, null: false, default: 0
    end

    create unique_index(:monthly_views, [:account_id, :month])
  end
end
