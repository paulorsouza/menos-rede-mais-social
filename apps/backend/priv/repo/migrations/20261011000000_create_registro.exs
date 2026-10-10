defmodule RedeSocial.Repo.Migrations.CreateRegistro do
  use Ecto.Migration

  def up do
    create table(:registro_entries, primary_key: false) do
      # Posição na árvore, a partir de 0. É também o índice das provas.
      add :position, :bigint, primary_key: true
      add :kind, :string, null: false
      # O texto exato da folha. Quem quiser confere: hash = SHA-256(0x00 || data).
      add :data, :text, null: false
      add :leaf_hash, :binary, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    # O registro só aceita acréscimos. A trava fica no próprio banco, para
    # valer também para quem acessa o banco por fora do backend.
    execute """
    CREATE FUNCTION registro_somente_acrescimos() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'o registro público só aceita acréscimos';
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER registro_sem_alteracao
    BEFORE UPDATE OR DELETE ON registro_entries
    FOR EACH ROW EXECUTE FUNCTION registro_somente_acrescimos()
    """

    execute """
    CREATE TRIGGER registro_sem_truncate
    BEFORE TRUNCATE ON registro_entries
    FOR EACH STATEMENT EXECUTE FUNCTION registro_somente_acrescimos()
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS registro_sem_truncate ON registro_entries"
    execute "DROP TRIGGER IF EXISTS registro_sem_alteracao ON registro_entries"
    execute "DROP FUNCTION IF EXISTS registro_somente_acrescimos()"
    drop table(:registro_entries)
  end
end
