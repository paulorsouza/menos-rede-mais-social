defmodule RedeSocial.Repo.Migrations.CreateTransparencyReports do
  use Ecto.Migration

  def change do
    # O relatório de transparência de cada trimestre, como foi publicado. O
    # texto fica exatamente como saiu, para o hash no registro público bater.
    create table(:transparency_reports) do
      add :quarter, :string, null: false
      add :body, :text, null: false
      add :sha256, :string, null: false
      add :registro_position, :integer
      add :published_at, :utc_datetime, null: false
    end

    create unique_index(:transparency_reports, [:quarter])
  end
end
