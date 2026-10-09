defmodule RedeSocial.Ads do
  @moduledoc """
  Anúncios nos shorts e o painel do criador.

  As contas de dinheiro (rateio dos shorts e faixas de pagamento) são feitas
  pelo motor de anúncios em Rust, com os parâmetros públicos de params/ads.toml.
  """

  import Ecto.Query

  alias RedeSocial.{Accounts, Engine, Feed, Repo, Social}
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Ads.{Campaign, Impression}

  @default_ad_every 6

  ## Shorts com anúncio

  @doc """
  Feed de shorts com um anúncio depois de cada bloco completo de shorts. O
  anúncio leva junto os ids dos shorts do bloco, para o rateio.
  """
  def shorts_feed(%Account{} = viewer, mode, now \\ DateTime.utc_now()) do
    {:ok, feed} = Feed.build(viewer, mode, [:short], now)
    every = shorts_ad_every()
    campaigns = active_campaigns(Date.utc_today())

    items =
      feed.entries
      |> Enum.chunk_every(every)
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, slot} ->
        shorts = Enum.map(block, &{:short, &1})

        campaign =
          if length(block) == every and not Accounts.minor?(viewer),
            do: pick_campaign(campaigns, viewer, slot)

        if campaign,
          do: shorts ++ [{:ad, campaign, Enum.map(block, & &1.post.id)}],
          else: shorts
      end)

    {:ok, Map.merge(feed, %{items: items, ad_every: every})}
  end

  defp shorts_ad_every do
    case Engine.transparency() do
      {:ok, %{"shorts_ad_every" => every}} when is_integer(every) and every > 0 -> every
      _ -> @default_ad_every
    end
  end

  def active_campaigns(today) do
    Campaign
    |> where([c], c.starts_on <= ^today and c.ends_on >= ^today)
    |> order_by([c], asc: c.id)
    |> Repo.all()
  end

  @doc """
  Escolhe o anúncio de um bloco. Quem tem anúncio regional da própria cidade vê
  o regional nos blocos pares e o nacional nos ímpares. O resto vê o nacional.
  """
  def pick_campaign(campaigns, %Account{region: region}, slot) do
    regional = Enum.filter(campaigns, &(&1.scope == :regional and &1.region == region))
    national = Enum.filter(campaigns, &(&1.scope == :national))

    cond do
      regional != [] and rem(slot, 2) == 0 -> rotate(regional, div(slot, 2))
      national != [] -> rotate(national, div(slot, 2))
      regional != [] -> rotate(regional, slot)
      true -> nil
    end
  end

  defp rotate(list, position), do: Enum.at(list, rem(position, length(list)))

  @doc """
  Registra que o anúncio foi visto e divide a receita entre os criadores dos
  shorts anteriores, proporcional ao tempo assistido. Quem desligou anúncios,
  ou não pode receber, fica fora do rateio.
  """
  def record_impression(%Account{} = viewer, campaign_id, watched) when is_list(watched) do
    with false <- Accounts.minor?(viewer),
         %Campaign{} = campaign <- Repo.get(Campaign, campaign_id),
         breakdown when breakdown != [] <- breakdown(watched),
         {:ok, splits} <- split(campaign.cents_per_impression, breakdown) do
      %Impression{
        campaign_id: campaign.id,
        viewer_id: viewer.id,
        revenue_cents: campaign.cents_per_impression,
        splits: splits,
        breakdown: breakdown
      }
      |> Repo.insert()
    else
      true -> {:error, :not_found}
      nil -> {:error, :not_found}
      [] -> {:error, :no_shorts}
      {:error, _reason} -> {:error, :engine_unavailable}
    end
  end

  defp breakdown(watched) do
    watched_by_post =
      for %{"post_id" => post_id, "watched_ms" => ms} <- Enum.take(watched, 12),
          is_integer(post_id) and is_integer(ms),
          into: %{},
          do: {post_id, ms |> max(0) |> min(600_000)}

    watched_by_post
    |> Map.keys()
    |> Social.get_posts()
    |> Enum.filter(&(&1.kind == :short))
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn post ->
      %{
        "post_id" => post.id,
        "author_id" => post.author_id,
        "nickname" => post.author.nickname,
        "watched_ms" => Map.fetch!(watched_by_post, post.id),
        "monetized" => post.monetized and Accounts.can_monetize?(post.author)
      }
    end)
  end

  defp split(revenue_cents, breakdown) do
    authors = breakdown |> Enum.map(& &1["author_id"]) |> Enum.uniq() |> Enum.sort()
    index = authors |> Enum.with_index(1) |> Map.new()
    reverse = Map.new(index, fn {author, number} -> {Integer.to_string(number), author} end)

    views =
      Enum.map(breakdown, fn item ->
        %{
          creator_id: Map.fetch!(index, item["author_id"]),
          watched_ms: item["watched_ms"],
          monetized: item["monetized"]
        }
      end)

    with {:ok, %{"cents_by_creator" => cents}} <- Engine.split_shorts(revenue_cents, views) do
      {:ok, Map.new(cents, fn {number, value} -> {Map.fetch!(reverse, number), value} end)}
    end
  end

  ## Painel do criador

  def dashboard(%Account{} = account) do
    month = Social.current_month()
    views = Social.monthly_views(account, month)
    cents_per_thousand = Application.fetch_env!(:rede_social, :base_cents_per_thousand)

    with {:ok, payout} <- Engine.payout(views, cents_per_thousand),
         {:ok, transparency} <- Engine.transparency() do
      bands = transparency["payout_bands"]

      {:ok,
       %{
         month: month,
         monetizable: Accounts.can_monetize?(account),
         views: views,
         cents_per_thousand: cents_per_thousand,
         effective_views: payout["effective_views"],
         payout_cents: payout["payout_cents"],
         params_version: payout["params_version"],
         bands: bands,
         current_band: current_band(bands, views),
         shorts: shorts_earnings(account)
       }}
    else
      {:error, _reason} -> {:error, :engine_unavailable}
    end
  end

  defp current_band(bands, views) do
    Enum.find_index(bands, fn band -> is_nil(band["up_to"]) or views <= band["up_to"] end)
  end

  def shorts_earnings(%Account{id: id}) do
    query =
      from i in Impression,
        where: fragment("(? ->> ?) IS NOT NULL", i.splits, ^id)

    total =
      Repo.one(
        from i in query,
          select: fragment("COALESCE(SUM((? ->> ?)::bigint), 0)::bigint", i.splits, ^id)
      )

    recent =
      query
      |> order_by([i], desc: i.inserted_at, desc: i.id)
      |> limit(10)
      |> preload(:campaign)
      |> Repo.all()
      |> Enum.map(fn impression ->
        mine = Enum.filter(impression.breakdown, &(&1["author_id"] == id))

        %{
          at: impression.inserted_at,
          advertiser: impression.campaign.advertiser,
          scope: impression.campaign.scope,
          revenue_cents: impression.revenue_cents,
          my_cents: Map.get(impression.splits, id, 0),
          my_watched_ms: Enum.sum(Enum.map(mine, & &1["watched_ms"])),
          total_watched_ms: Enum.sum(Enum.map(impression.breakdown, & &1["watched_ms"])),
          creators: length(Enum.uniq(Enum.map(impression.breakdown, & &1["author_id"])))
        }
      end)

    %{
      total_cents: total,
      count: Repo.aggregate(query, :count),
      recent: recent
    }
  end

  ## Biblioteca pública de anúncios

  def library do
    Campaign
    |> order_by([c], asc: c.scope, asc: c.advertiser)
    |> Repo.all()
  end
end
