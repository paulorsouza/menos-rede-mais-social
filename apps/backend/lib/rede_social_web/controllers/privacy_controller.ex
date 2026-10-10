defmodule RedeSocialWeb.PrivacyController do
  @moduledoc "Baixar os próprios dados e apagar a conta (regra pétrea 11)."
  use RedeSocialWeb, :controller

  alias RedeSocial.Privacy
  alias RedeSocialWeb.Auth

  action_fallback RedeSocialWeb.FallbackController

  def export(conn, _params) do
    account = conn.assigns.current_account
    body = Jason.encode_to_iodata!(Privacy.export(account), pretty: true)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="rede-social-#{account.nickname}.json")
    )
    |> send_resp(200, body)
  end

  def delete(conn, params) do
    with :ok <- Privacy.delete_account(conn.assigns.current_account, params["nickname"]) do
      conn |> Auth.log_out() |> json(%{ok: true})
    end
  end
end
