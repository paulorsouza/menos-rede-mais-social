defmodule RedeSocial.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nickname, :string, null: false
      add :govbr_level, :string
      add :age_band, :string
      add :cpf_fingerprint, :binary
      add :cpf_ciphertext, :binary

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:nickname])
    # Contas básicas não têm CPF; o Postgres aceita vários NULL num índice único.
    create unique_index(:accounts, [:cpf_fingerprint])
  end
end
