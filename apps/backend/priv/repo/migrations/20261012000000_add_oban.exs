defmodule RedeSocial.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Fila de trabalhos (transcodificação e legendas) no próprio PostgreSQL.
  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 1)
end
