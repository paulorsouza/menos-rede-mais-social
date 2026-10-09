defmodule RedeSocialWeb.Auth do
  @moduledoc """
  Sessão da pessoa logada. Na demonstração o login vem do gov.br simulado;
  com o gov.br de verdade (OpenID Connect) só muda quem chama `log_in/2`.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias RedeSocial.Accounts

  def init(action), do: action

  def call(conn, :fetch_current_account) do
    account = conn |> get_session(:account_id) |> Accounts.get_account()

    # Registro de acesso do Marco Civil: no máximo um por hora, com o IP selado.
    if account, do: RedeSocial.AccessLogs.record(account, conn.remote_ip)

    assign(conn, :current_account, account)
  end

  def call(conn, :require_account) do
    if conn.assigns[:current_account] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Entre na sua conta para continuar."})
      |> halt()
    end
  end

  def call(conn, :require_moderator) do
    case conn.assigns[:current_account] do
      %{moderator: true} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Só a equipe de moderação pode fazer isso."})
        |> halt()
    end
  end

  def call(conn, :require_legal_officer) do
    case conn.assigns[:current_account] do
      %{legal_officer: true} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Só o setor jurídico da entidade gestora pode fazer isso."})
        |> halt()
    end
  end

  def call(conn, :require_demo_mode) do
    if RedeSocial.Demo.enabled?() do
      conn
    else
      conn |> put_status(:not_found) |> json(%{error: "Não encontrado."}) |> halt()
    end
  end

  def log_in(conn, account) do
    conn
    |> configure_session(renew: true)
    |> put_session(:account_id, account.id)
  end

  def log_out(conn), do: configure_session(conn, drop: true)
end
