defmodule RedeSocialWeb.TransparencyController do
  use RedeSocialWeb, :controller

  alias RedeSocial.Transparency
  alias RedeSocial.Transparency.Quarterly
  alias RedeSocialWeb.Present

  action_fallback RedeSocialWeb.FallbackController

  def show(conn, _params) do
    report = Transparency.report()
    json(conn, %{report | ads: Enum.map(report.ads, &Present.campaign_record/1)})
  end

  @doc """
  O relatório de um trimestre, exatamente como foi publicado: o SHA-256 deste
  texto é o que está no registro público.
  """
  def quarterly(conn, %{"quarter" => quarter}) do
    case Quarterly.get(quarter) do
      nil ->
        {:error, :not_found}

      report ->
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="transparencia-#{report.quarter}.json")
        )
        |> send_resp(200, report.body)
    end
  end
end
