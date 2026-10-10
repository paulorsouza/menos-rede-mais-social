defmodule RedeSocial.Repo.Migrations.CreateModeration do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :moderator, :boolean, null: false, default: false
    end

    alter table(:posts) do
      add :removal_rule, :integer
      add :removed_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
    end

    create table(:reports) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false

      add :reporter_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :rule, :integer, null: false
      add :resolution, :string
      add :resolved_at, :utc_datetime
      add :resolved_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:reports, [:post_id, :reporter_id])
    create index(:reports, [:resolved_at])

    create table(:appeals) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false

      add :author_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false

      add :text, :text
      add :outcome, :string
      add :decided_at, :utc_datetime
      add :decided_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:appeals, [:post_id])

    create table(:notices) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :post_id, references(:posts, on_delete: :delete_all)
      add :kind, :string, null: false
      add :rule, :integer
      add :read_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notices, [:account_id, :inserted_at])

    # Registro das decisões da moderação, de onde saem os números públicos.
    # Só recebe linhas novas; apagar uma conta ou um post não apaga o que
    # foi decidido, só desliga o vínculo.
    create table(:moderation_actions) do
      add :action, :string, null: false
      add :rule, :integer
      add :post_id, references(:posts, on_delete: :nilify_all)
      add :moderator_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:moderation_actions, [:action])
  end
end
