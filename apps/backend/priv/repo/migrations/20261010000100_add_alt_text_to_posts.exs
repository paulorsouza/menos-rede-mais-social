defmodule RedeSocial.Repo.Migrations.AddAltTextToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # Descrição da foto para quem usa leitor de tela.
      add :alt_text, :text
    end
  end
end
