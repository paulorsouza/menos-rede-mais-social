defmodule RedeSocial.Accounts.Account do
  @moduledoc """
  Uma conta da rede. O perfil público mostra só o apelido e, quando a conta
  entrou pelo gov.br, o selo de pessoa verificada.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :nickname, :string
    field :bio, :string

    # Cidade/UF informada pela pessoa. Serve só para escolher anúncio regional.
    field :region, :string

    # Nível da conta gov.br. Fica vazio na conta básica, que não tem selo.
    field :govbr_level, Ecto.Enum, values: [:bronze, :prata, :ouro]
    field :age_band, Ecto.Enum, values: [:minor, :adult]

    # HMAC do CPF: impede contas duplicadas sem guardar o número.
    field :cpf_fingerprint, :binary, redact: true

    # Cópia do CPF selada com a chave dos guardiões: só abre com ordem
    # judicial e 3 de 5 guardiões (seção 3 do plano).
    field :cpf_ciphertext, :binary, redact: true

    # Pessoa da equipe de moderação. Não se ganha pelo app: quem concede é a
    # entidade gestora, sempre com duas pessoas.
    field :moderator, :boolean, default: false

    # Setor jurídico da entidade gestora: registra ordens judiciais. Também só
    # se ganha pela entidade gestora.
    field :legal_officer, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @nickname_format ~r/^[a-z0-9_.]{3,30}$/

  @doc "Conta básica, sem gov.br."
  def basic_changeset(account, attrs) do
    account
    |> cast(attrs, [:nickname, :region, :bio])
    |> validate_nickname()
    |> validate_profile()
  end

  @doc "Conta verificada pelo gov.br. A impressão digital do CPF já vem no struct."
  def verified_changeset(account, attrs) do
    account
    |> cast(attrs, [:nickname, :govbr_level, :age_band, :region, :bio])
    |> validate_required([:govbr_level, :age_band, :cpf_fingerprint])
    |> validate_nickname()
    |> validate_profile()
    |> unique_constraint(:cpf_fingerprint, message: "já existe uma conta para esta pessoa")
  end

  defp validate_nickname(changeset) do
    changeset
    |> update_change(:nickname, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:nickname])
    |> validate_format(:nickname, @nickname_format,
      message: "use de 3 a 30 caracteres: letras sem acento, números, ponto ou sublinhado"
    )
    |> unique_constraint(:nickname, message: "este apelido já está em uso")
  end

  defp validate_profile(changeset) do
    changeset
    |> validate_length(:bio, max: 160)
    |> validate_length(:region, max: 60)
  end
end
