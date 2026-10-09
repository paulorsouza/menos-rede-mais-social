defmodule RedeSocialWeb.SessionController do
  use RedeSocialWeb, :controller

  alias RedeSocial.Accounts
  alias RedeSocialWeb.{Auth, Present}

  action_fallback RedeSocialWeb.FallbackController

  def show(conn, _params) do
    json(conn, %{account: Present.me(conn.assigns.current_account)})
  end

  @doc "Entrar numa conta já existente. Só existe no modo de demonstração."
  def create(conn, %{"nickname" => nickname}) do
    with %{} = account <- Accounts.get_by_nickname(nickname) do
      conn
      |> Auth.log_in(account)
      |> json(%{account: Present.me(account)})
    end
  end

  def delete(conn, _params) do
    conn
    |> Auth.log_out()
    |> json(%{ok: true})
  end
end
