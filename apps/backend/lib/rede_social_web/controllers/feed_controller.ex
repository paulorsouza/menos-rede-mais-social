defmodule RedeSocialWeb.FeedController do
  use RedeSocialWeb, :controller

  alias RedeSocial.{Accounts, Ads, Feed}
  alias RedeSocialWeb.Present

  action_fallback RedeSocialWeb.FallbackController

  @doc """
  Feed de textos e fotos (kind=home), de vídeos e lives (kind=videos) ou de
  tudo (kind=all, usado pela aba "Em alta").
  """
  def index(conn, params) do
    mode = Map.get(params, "mode", "mixed")
    kinds = kinds(params["kind"])

    if Feed.valid_mode?(mode) do
      viewer = conn.assigns.current_account
      {:ok, feed} = Feed.build(viewer, mode, kinds)

      # Nos vídeos, o anúncio entra nos pontos que o criador marcou. O player
      # recebe o anúncio escolhido para esta pessoa (regional, se houver).
      ad =
        if :video in kinds and not Accounts.minor?(viewer) do
          Date.utc_today() |> Ads.active_campaigns() |> Ads.pick_campaign(viewer, 0)
        end

      json(conn, %{
        mode: feed.mode,
        engine: feed.engine,
        items: Enum.map(feed.entries, &Present.entry/1),
        ad: ad && Present.campaign(ad)
      })
    else
      invalid_mode(conn)
    end
  end

  @doc "Shorts, com um anúncio depois de cada bloco."
  def shorts(conn, params) do
    mode = Map.get(params, "mode", "mixed")

    if Feed.valid_mode?(mode) do
      {:ok, feed} = Ads.shorts_feed(conn.assigns.current_account, mode)

      items =
        Enum.map(feed.items, fn
          {:short, entry} ->
            %{type: "short", post: Present.entry(entry)}

          {:ad, campaign, short_ids} ->
            %{type: "ad", ad: Present.campaign(campaign), short_ids: short_ids}
        end)

      json(conn, %{mode: feed.mode, engine: feed.engine, ad_every: feed.ad_every, items: items})
    else
      invalid_mode(conn)
    end
  end

  @doc "A conta do feed (entrada, saída e recibo), para baixar e conferir."
  def account(conn, params) do
    mode = Map.get(params, "mode", "mixed")
    kinds = kinds(params["kind"])

    with true <- Feed.valid_mode?(mode) || :invalid,
         {:ok, account} <- Feed.account(conn.assigns.current_account, mode, kinds) do
      conn
      |> put_resp_header("content-disposition", ~s(attachment; filename="conta-do-feed.json"))
      |> json(account)
    else
      :invalid -> invalid_mode(conn)
      error -> error
    end
  end

  defp kinds("videos"), do: [:video, :live]
  defp kinds("all"), do: [:text, :photo, :video, :short, :live]
  defp kinds("shorts"), do: [:short]
  defp kinds(_home), do: [:text, :photo]

  defp invalid_mode(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Modo de feed desconhecido.", modes: Feed.modes()})
  end
end
