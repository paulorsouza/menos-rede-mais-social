defmodule RedeSocialWeb.CreatorController do
  use RedeSocialWeb, :controller

  alias RedeSocial.Ads

  action_fallback RedeSocialWeb.FallbackController

  def show(conn, _params) do
    with {:ok, dashboard} <- Ads.dashboard(conn.assigns.current_account) do
      json(conn, dashboard)
    end
  end
end
