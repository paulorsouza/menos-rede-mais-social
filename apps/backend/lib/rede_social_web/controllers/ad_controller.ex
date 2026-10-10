defmodule RedeSocialWeb.AdController do
  use RedeSocialWeb, :controller

  alias RedeSocial.Ads

  action_fallback RedeSocialWeb.FallbackController

  @doc """
  O app avisa que um anúncio dos shorts foi visto e manda quanto tempo a pessoa
  assistiu de cada short do bloco. O rateio é calculado pelo motor.
  """
  def impression(conn, %{"campaign_id" => campaign_id, "watched" => watched})
      when is_list(watched) do
    with {:ok, impression} <-
           Ads.record_impression(conn.assigns.current_account, campaign_id, watched) do
      conn
      |> put_status(:created)
      |> json(%{revenue_cents: impression.revenue_cents, splits: impression.splits})
    end
  end

  def impression(_conn, _params), do: {:error, :no_shorts}

  @doc """
  O app avisa que um anúncio passou dentro de um vídeo, num dos pontos que o
  criador marcou. É a base do pagamento por faixas.
  """
  def view(conn, %{"campaign_id" => campaign_id, "post_id" => post_id, "moment" => moment}) do
    with {:ok, _view} <-
           Ads.record_ad_view(conn.assigns.current_account, campaign_id, post_id, moment) do
      send_resp(conn, :no_content, "")
    end
  end

  def view(_conn, _params), do: {:error, :not_found}
end
