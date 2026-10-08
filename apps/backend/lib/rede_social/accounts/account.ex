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

    # Nível da conta gov.br. Fica vazio na conta básica, que não tem selo.
    field :govbr_level, Ecto.Enum, values: [:bronze, :prata, :ouro]
    field :age_band, Ecto.Enum, values: [:minor, :adult]

    # HMAC do CPF: impede contas duplicadas sem guardar o número.
    field :cpf_fingerprint, :binary, redact: true

    # Cópia cifrada do CPF, que só 3 de 5 guardiões conseguem abrir, e só com
    # ordem judicial (seção 3 do plano). Fica vazia até esse esquema existir.
    field :cpf_ciphertext, :binary, redact: true

    timestamps(type: :utc_datetime)
  end

  @nickname_format ~r/^[a-z0-9_.]{3,30}$/

  @doc "Conta básica, sem gov.br."
  def basic_changeset(account, attrs) do
    account
    |> cast(attrs, [:nickname])
    |> validate_nickname()
  end

  @doc "Conta verificada pelo gov.br. A impressão digital do CPF já vem no struct."
  def verified_changeset(account, attrs) do
    account
    |> cast(attrs, [:nickname, :govbr_level, :age_band])
    |> validate_required([:govbr_level, :age_band, :cpf_fingerprint])
    |> validate_nickname()
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
end
