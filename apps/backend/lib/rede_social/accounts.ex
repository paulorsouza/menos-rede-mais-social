defmodule RedeSocial.Accounts do
  @moduledoc """
  Contas da rede.

  Cada pessoa entra pelo gov.br e aparece com um apelido. A rede guarda o
  mínimo sobre quem ela é: a impressão digital do CPF, para impedir contas
  duplicadas, e uma cópia selada com a chave dos guardiões, que só abre com
  ordem judicial e 3 de 5 guardiões (RedeSocial.Identification).
  """

  import Ecto.Query

  alias RedeSocial.Accounts.{Account, CPF}
  alias RedeSocial.{Repo, Vault}

  @doc """
  Cria uma conta verificada pelo gov.br.

  O CPF sai daqui de dois jeitos, e nenhum em texto: a impressão digital, que
  barra contas duplicadas, e a cópia selada pelo motor com a chave dos
  guardiões, amarrada ao id da conta. Sem o motor, a conta não é criada: uma
  conta sem a cópia selada não poderia cumprir uma ordem judicial.
  """
  def register_verified(attrs, cpf) do
    id = Ecto.UUID.generate()

    with {:ok, normalized} <- CPF.normalize(cpf),
         {:ok, sealed} <- seal_cpf(normalized, id) do
      %Account{
        id: id,
        cpf_fingerprint: CPF.fingerprint(normalized, fingerprint_key()),
        cpf_ciphertext: sealed
      }
      |> Account.verified_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "A conta de quem tem este CPF, achada pela impressão digital."
  def get_by_cpf(cpf) do
    case CPF.normalize(cpf) do
      {:ok, normalized} ->
        Repo.get_by(Account, cpf_fingerprint: CPF.fingerprint(normalized, fingerprint_key()))

      {:error, _reason} ->
        nil
    end
  end

  @doc "O nível da conta gov.br muda com o tempo; a cada login ele é atualizado."
  def update_govbr_level(%Account{} = account, level) do
    account |> Ecto.Changeset.change(govbr_level: level) |> Repo.update()
  end

  @doc "O contexto amarra o CPF selado à conta: copiado para outra, ele não abre."
  def cpf_context(account_id), do: "cpf:" <> account_id

  defp seal_cpf(cpf, account_id) do
    case Vault.seal(cpf, cpf_context(account_id)) do
      {:ok, sealed} -> {:ok, sealed}
      {:error, _reason} -> {:error, :vault_unavailable}
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

  def get_account(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Account, uuid)
      :error -> nil
    end
  end

  def get_account(_id), do: nil

  def get_by_nickname(nickname) when is_binary(nickname) do
    Repo.get_by(Account, nickname: String.downcase(nickname))
  end

  @doc "Contas na ordem dos apelidos pedidos. Apelidos que não existem ficam de fora."
  def list_by_nicknames(nicknames) do
    accounts = Repo.all(from a in Account, where: a.nickname in ^nicknames)
    by_nickname = Map.new(accounts, &{&1.nickname, &1})

    nicknames
    |> Enum.map(&Map.get(by_nickname, &1))
    |> Enum.reject(&is_nil/1)
  end

  @doc "Se a conta mostra o selo de pessoa verificada."
  def verified?(%Account{govbr_level: level}), do: not is_nil(level)

  @doc "Receber por anúncios exige gov.br prata ou ouro e ser maior de idade."
  def can_monetize?(%Account{govbr_level: level} = account),
    do: level in [:prata, :ouro] and not minor?(account)

  @doc """
  Menor de idade, pela faixa que veio do gov.br. Menores têm perfil privado
  por padrão e não veem nem recebem anúncios (seção 3 do plano, ECA Digital).
  """
  def minor?(%Account{age_band: :minor}), do: true
  def minor?(_account), do: false

  def count_by_kind do
    verified = Repo.aggregate(from(a in Account, where: not is_nil(a.govbr_level)), :count)
    basic = Repo.aggregate(from(a in Account, where: is_nil(a.govbr_level)), :count)
    %{verified: verified, basic: basic}
  end

  defp fingerprint_key, do: Application.fetch_env!(:rede_social, :cpf_fingerprint_key)
end
