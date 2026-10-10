defmodule RedeSocial.AccessLogs do
  @moduledoc """
  Registros de acesso que o Marco Civil (art. 15) manda guardar por seis
  meses: IP, data e hora.

  A data fica aberta, porque é ela que diz quando o registro precisa sumir.
  O IP fica selado com a chave dos guardiões, igual ao CPF: só sai com ordem
  judicial e com 3 dos 5 guardiões. Para não encher o banco, cada conta ganha
  no máximo um registro por hora. Passados seis meses, o registro é apagado.

  O registro não tem vínculo forte com a conta: se a pessoa apagar a conta, a
  lei ainda manda guardar os acessos até o fim do prazo.
  """

  import Ecto.Query

  require Logger

  alias RedeSocial.Accounts.Account
  alias RedeSocial.{AccessLogs.AccessLog, Repo, Vault}

  @interval_seconds 3600
  @retention_days 183

  def retention_days, do: @retention_days

  @doc "Guarda o acesso, se a conta não tiver nenhum na última hora."
  def record(%Account{id: account_id}, ip) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    since = DateTime.add(now, -@interval_seconds, :second)

    recent? =
      Repo.exists?(
        from l in AccessLog, where: l.account_id == ^account_id and l.inserted_at > ^since
      )

    if recent?, do: :ok, else: insert(account_id, format_ip(ip), now)
  end

  defp insert(account_id, ip, now) do
    case Vault.seal(ip, context(account_id, now)) do
      {:ok, sealed} ->
        Repo.insert!(%AccessLog{account_id: account_id, sealed: sealed, inserted_at: now})
        :ok

      {:error, reason} ->
        # Sem o motor, o acesso não é registrado, mas a pessoa continua entrando.
        Logger.warning("registro de acesso não guardado: #{inspect(reason)}")
        :error
    end
  end

  @doc "O contexto amarra o IP selado à conta e ao momento do acesso."
  def context(account_id, %DateTime{} = at), do: "acesso:#{account_id}:#{DateTime.to_unix(at)}"

  def for_account(account_id) do
    Repo.all(
      from l in AccessLog,
        where: l.account_id == ^account_id,
        order_by: [desc: l.inserted_at, desc: l.id]
    )
  end

  @doc "Apaga o que passou do prazo da lei."
  def purge(now \\ DateTime.utc_now()) do
    limit = DateTime.add(now, -@retention_days * 86_400, :second)
    {count, _} = Repo.delete_all(from l in AccessLog, where: l.inserted_at < ^limit)
    count
  end

  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_ip), do: "desconhecido"
end
