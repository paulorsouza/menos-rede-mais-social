defmodule RedeSocialWeb.GovBrController do
  @moduledoc """
  Entrar com o gov.br de verdade. A volta do gov.br termina sempre num
  redirecionamento para o app: conta que já existe entra direto; conta nova
  vai escolher o apelido, e só então a conta é criada.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.{Accounts, GovBr}
  alias RedeSocialWeb.{Auth, Present}

  action_fallback RedeSocialWeb.FallbackController

  # Quanto tempo a pessoa tem para escolher o apelido depois do gov.br.
  @pending_seconds 600

  def status(conn, _params), do: json(conn, %{enabled: GovBr.enabled?()})

  def start(conn, _params) do
    if GovBr.enabled?() do
      flow = GovBr.new_flow()

      conn
      |> put_session(:govbr_flow, flow)
      |> redirect(external: GovBr.authorize_url(flow))
    else
      {:error, :govbr_disabled}
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    flow = get_session(conn, :govbr_flow)
    conn = delete_session(conn, :govbr_flow)

    with %{"state" => ^state} <- flow,
         {:ok, id_token} <- GovBr.exchange(code, flow),
         {:ok, identity} <- GovBr.identity(id_token, flow) do
      case Accounts.get_by_cpf(identity.cpf) do
        %{} = account ->
          {:ok, account} = Accounts.update_govbr_level(account, identity.level)
          conn |> Auth.log_in(account) |> redirect(to: "/")

        nil ->
          conn
          |> put_session(:govbr_pending, Map.put(identity, :at, System.system_time(:second)))
          |> redirect(to: "/entrar?govbr=apelido")
      end
    else
      _ -> redirect(conn, to: "/entrar?govbr=erro")
    end
  end

  def callback(conn, _params), do: redirect(conn, to: "/entrar?govbr=erro")

  @doc "Conta nova: o gov.br já confirmou quem é; falta o apelido."
  def register(conn, params) do
    with %{cpf: cpf, level: level, age_band: age_band, at: at} <-
           get_session(conn, :govbr_pending),
         true <- System.system_time(:second) - at < @pending_seconds,
         attrs =
           params
           |> Map.take(~w(nickname region bio))
           |> Map.merge(%{"govbr_level" => level, "age_band" => age_band}),
         {:ok, account} <- Accounts.register_verified(attrs, cpf) do
      conn
      |> delete_session(:govbr_pending)
      |> Auth.log_in(account)
      |> put_status(:created)
      |> json(%{account: Present.me(account)})
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :govbr_expired}
    end
  end
end
