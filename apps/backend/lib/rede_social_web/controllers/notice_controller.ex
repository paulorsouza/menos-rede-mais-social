defmodule RedeSocialWeb.NoticeController do
  @moduledoc "Avisos da moderação para quem publicou."
  use RedeSocialWeb, :controller

  alias RedeSocial.Moderation
  alias RedeSocialWeb.Present

  def index(conn, _params) do
    notices = Moderation.notices(conn.assigns.current_account)
    json(conn, %{notices: Enum.map(notices, &Present.notice/1)})
  end

  def read(conn, _params) do
    :ok = Moderation.mark_read(conn.assigns.current_account)
    json(conn, %{ok: true})
  end
end
