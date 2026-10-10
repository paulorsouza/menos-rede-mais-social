defmodule RedeSocial.Repo.Migrations.AddProfileToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # Cidade e UF informadas pela pessoa. Usadas só para anúncio regional.
      add :region, :string
      add :bio, :string
    end
  end
end
