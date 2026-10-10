defmodule RedeSocial.Repo.Migrations.CreateRemovalRequests do
  use Ecto.Migration

  def change do
    # Pedidos de remoção vindos de fora (juízo ou outro órgão), pelo canal
    # formal do setor jurídico. Todos entram no relatório de transparência.
    create table(:removal_requests) do
      add :post_id, references(:posts, on_delete: :nilify_all)
      add :requested_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      # "judicial" ou "outro" (ministério, partido, empresa...).
      add :kind, :string, null: false
      add :authority, :string, null: false
      add :legal_basis, :string, null: false
      add :case_number, :string
      add :secret_case, :boolean, null: false, default: false
      # "recebido", "cumprido" ou "recusado".
      add :status, :string, null: false, default: "recebido"
      add :rule, :integer
      add :refusal_reason, :text
      add :decided_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime
      add :registro_position, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:removal_requests, [:inserted_at])
  end
end
