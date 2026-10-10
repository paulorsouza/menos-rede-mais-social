defmodule RedeSocialWeb.TransparencyController do
  use RedeSocialWeb, :controller

  alias RedeSocial.Transparency
  alias RedeSocialWeb.Present

  def show(conn, _params) do
    report = Transparency.report()
    json(conn, %{report | ads: Enum.map(report.ads, &Present.campaign_record/1)})
  end
end
