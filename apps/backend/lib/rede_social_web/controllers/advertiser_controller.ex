defmodule RedeSocialWeb.AdvertiserController do
  @moduledoc """
  O lado de quem anuncia: cadastrar a empresa (CNPJ), ver o preço, criar a
  campanha e acompanhar análise, cobrança e entrega.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.Ads
  alias RedeSocialWeb.Present

  action_fallback RedeSocialWeb.FallbackController

  def show(conn, _params) do
    case Ads.advertiser(conn.assigns.current_account) do
      nil ->
        json(conn, %{advertiser: nil, campaigns: []})

      advertiser ->
        json(conn, %{
          advertiser: Present.advertiser(advertiser),
          campaigns: Enum.map(Ads.campaigns(advertiser), &Present.own_campaign/1)
        })
    end
  end

  def register(conn, params) do
    with {:ok, advertiser} <- Ads.register_advertiser(conn.assigns.current_account, params) do
      conn |> put_status(:created) |> json(%{advertiser: Present.advertiser(advertiser)})
    end
  end

  def price(conn, params) do
    with {:ok, %{quote: quote, days: days}} <- Ads.price(params) do
      json(conn, %{quote: Map.put(quote, "days", days)})
    end
  end

  def create(conn, params) do
    with {:ok, campaign} <- Ads.create_campaign(conn.assigns.current_account, params) do
      conn |> put_status(:created) |> json(%{campaign: Present.own_campaign(campaign)})
    end
  end
end
