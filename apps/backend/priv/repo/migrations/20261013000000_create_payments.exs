defmodule RedeSocial.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    # Quem anuncia: uma empresa, pelo CNPJ. CNPJ é público, e a biblioteca de
    # anúncios mostra quem pagou cada campanha.
    create table(:advertisers) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :cnpj, :string, null: false
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:advertisers, [:cnpj])
    create unique_index(:advertisers, [:account_id])

    # A campanha passa pela moderação, é paga por PIX e só então entra no ar.
    alter table(:ad_campaigns) do
      add :advertiser_id, references(:advertisers, on_delete: :nilify_all)
      add :status, :string, null: false, default: "active"
      add :impressions_per_day, :integer
      add :price_cents, :bigint
      add :rejection_rule, :integer
      add :reviewed_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime
      add :charge_txid, :string
      add :brcode, :text
      add :paid_at, :utc_datetime
    end

    create index(:ad_campaigns, [:status])

    # Anúncio dos shorts: a cidade de quem viu (para o ritmo de entrega) e o
    # que ficou com o fundo de infraestrutura.
    alter table(:ad_impressions) do
      add :viewer_region, :string
      add :fund_cents, :integer, null: false, default: 0
    end

    create index(:ad_impressions, [:inserted_at])

    # Anúncio que passou dentro de um vídeo. É o que conta para o pagamento
    # por faixas do criador.
    create table(:ad_views) do
      add :campaign_id, references(:ad_campaigns, on_delete: :delete_all), null: false
      add :post_id, references(:posts, on_delete: :delete_all), null: false

      add :creator_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :viewer_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :viewer_region, :string
      add :viewer_verified, :boolean, null: false
      add :regional, :boolean, null: false
      add :moment, :string, null: false
      add :revenue_cents, :integer, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ad_views, [:creator_id, :inserted_at])
    create index(:ad_views, [:campaign_id, :inserted_at])

    # Fechamento do mês: a raiz da árvore com as linhas de todos os extratos
    # vai para o registro público. O sal dos pseudônimos de quem viu nunca sai
    # daqui.
    create table(:payout_months) do
      add :month, :date, null: false
      add :salt, :binary, null: false
      add :root, :binary, null: false
      add :leaves_count, :integer, null: false
      add :registro_position, :integer
      add :params_sha256, :string, null: false
      add :revenue_cents, :bigint, null: false
      add :creators_cents, :bigint, null: false
      add :fund_cents, :bigint, null: false
      add :closed_at, :utc_datetime, null: false
    end

    create unique_index(:payout_months, [:month])

    create table(:payout_leaves, primary_key: false) do
      add :month_id, references(:payout_months, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :leaf_hash, :binary, null: false
    end

    create unique_index(:payout_leaves, [:month_id, :position])

    # O extrato de cada criador em cada mês, guardado como foi fechado: a
    # entrada e o resultado do motor. É ele que o criador baixa e confere.
    create table(:payouts) do
      add :month_id, references(:payout_months, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :input, :map, null: false
      add :result, :map, null: false
      add :total_cents, :bigint, null: false
      add :payable, :boolean, null: false
      add :status, :string, null: false
      add :pix_key_hint, :string
      add :pix_e2e_id, :string
      add :paid_at, :utc_datetime
      add :error, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:payouts, [:month_id, :account_id])
    create index(:payouts, [:account_id])

    # A chave PIX do criador. Não pode ser o CPF: a rede não guarda CPF em
    # texto. Na hora de cadastrar, o banco diz de quem é a chave, e a rede
    # confere pela impressão digital do CPF que é da própria pessoa.
    create table(:pix_keys, primary_key: false) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :key, :string, null: false
      add :kind, :string, null: false
      add :hint, :string, null: false
      add :verified_at, :utc_datetime, null: false
    end

    # Só na demonstração: o diretório de chaves PIX do banco simulado.
    create table(:demo_pix_directory, primary_key: false) do
      add :key, :string, primary_key: true
      add :document, :string, null: false
      add :name, :string, null: false
    end
  end
end
