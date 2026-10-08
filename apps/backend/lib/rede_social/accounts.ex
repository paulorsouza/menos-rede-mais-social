defmodule RedeSocial.Accounts do
  @moduledoc """
  Contas da rede.

  Cada pessoa entra pelo gov.br e aparece com um apelido. A rede guarda o
  mínimo sobre quem ela é: a impressão digital do CPF, para impedir contas
  duplicadas, e (quando o esquema de guardiões existir) uma cópia cifrada que
  só abre com ordem judicial.
  """

  alias RedeSocial.Accounts.{Account, CPF}
  alias RedeSocial.Repo

  @doc """
  Cria uma conta verificada pelo gov.br.
  """
  def register_verified(attrs, cpf) do
    with {:ok, normalized} <- CPF.normalize(cpf) do
      %Account{cpf_fingerprint: CPF.fingerprint(normalized, fingerprint_key())}
      |> Account.verified_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Cria uma conta básica, sem gov.br. Ela só pode ver, seguir e salvar.
  """
  def register_basic(attrs) do
    %Account{}
    |> Account.basic_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Se a conta mostra o selo de pessoa verificada."
  def verified?(%Account{govbr_level: level}), do: not is_nil(level)

  @doc "Receber por anúncios exige gov.br prata ou ouro."
  def can_monetize?(%Account{govbr_level: level}), do: level in [:prata, :ouro]

  defp fingerprint_key, do: Application.fetch_env!(:rede_social, :cpf_fingerprint_key)
end
