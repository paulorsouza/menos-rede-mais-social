defmodule RedeSocial.Ads do
  @moduledoc """
  Anúncios: quem anuncia, como a campanha é comprada, onde ela aparece e o
  painel do criador.

  As contas de dinheiro (preço, ritmo de entrega, rateio dos shorts e faixas
  de pagamento) são feitas pelo motor de anúncios em Rust, com os parâmetros
  públicos de params/ads.toml. Anúncio nenhum olha quem a pessoa é: só a
  cidade, para o anúncio regional.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias RedeSocial.{Accounts, Engine, Feed, Payments, Repo, Social}
  alias RedeSocial.Accounts.{Account, CNPJ}
  alias RedeSocial.Ads.{AdSlot, AdView, Advertiser, Campaign, Impression, Rules}
  alias RedeSocial.Payments.Pix
  alias RedeSocial.Social.{Post, View}

  @default_ad_every 6
  # O dia dos anúncios é o de Brasília.
  @brasilia_offset -3 * 3600

  ## Shorts com anúncio

  # Por quanto tempo um anúncio mostrado ainda pode ser contado.
  @slot_ttl_seconds 3 * 3600
  # Folga entre o relógio do app e o do servidor no tempo assistido.
  @watch_slack_ms 5_000

  @doc """
  Feed de shorts com um anúncio depois de cada bloco completo de shorts. O
  anúncio leva junto os ids dos shorts do bloco, para o rateio, e o id da
  exibição: só conta anúncio que a rede mostrou, com os shorts que ela mostrou.
  """
  def shorts_feed(%Account{} = viewer, mode, now \\ DateTime.utc_now()) do
    {:ok, feed} = Feed.build(viewer, mode, [:short], now)
    every = shorts_ad_every()
    blocks = Enum.chunk_every(feed.entries, every)
    full_blocks = Enum.count(blocks, &(length(&1) == every))
    campaigns = if Accounts.minor?(viewer), do: [], else: pick_campaigns(viewer, full_blocks, now)

    {items, _rest} =
      Enum.flat_map_reduce(blocks, campaigns, fn block, remaining ->
        shorts = Enum.map(block, &{:short, &1})

        case {length(block) == every, remaining} do
          {true, [campaign | rest]} ->
            ids = Enum.map(block, & &1.post.id)
            slot = serve(viewer, campaign, :shorts, ids, now)
            {shorts ++ [{:ad, campaign, ids, slot.id}], rest}

          _ ->
            {shorts, remaining}
        end
      end)

    {:ok, Map.merge(feed, %{items: items, ad_every: every})}
  end

  @doc """
  O anúncio dos vídeos de um feed: a campanha que o motor escolheu e a
  exibição, que vale para os pontos de anúncio desses vídeos.
  """
  def video_ad(%Account{} = viewer, post_ids, now \\ DateTime.utc_now()) do
    with false <- Accounts.minor?(viewer),
         [campaign] <- pick_campaigns(viewer, 1, now) do
      {campaign, serve(viewer, campaign, :video, post_ids, now)}
    else
      _ -> nil
    end
  end

  defp serve(viewer, campaign, kind, post_ids, now) do
    Repo.insert!(%AdSlot{
      viewer_id: viewer.id,
      campaign_id: campaign.id,
      kind: kind,
      post_ids: post_ids,
      served_at: DateTime.truncate(now, :second)
    })
  end

  # A exibição desta pessoa, ainda no prazo.
  defp open_slot(%Account{id: viewer_id}, slot_id, kind, now) do
    oldest = DateTime.add(now, -@slot_ttl_seconds, :second)

    case to_integer(slot_id) && Repo.get(AdSlot, to_integer(slot_id)) do
      %AdSlot{viewer_id: ^viewer_id, kind: ^kind} = slot ->
        if DateTime.compare(slot.served_at, oldest) != :lt, do: slot

      _ ->
        nil
    end
  end

  @doc """
  Encerra as campanhas cujo último dia já passou e devolve por PIX, a quem
  pagou, o que não foi entregue: as exibições compradas que não saíram,
  pelo preço de cada uma. Se o banco falhar, a campanha fica para a próxima
  rodada; ela já não entrega mais, porque passou das datas.
  """
  def close_ended_campaigns(now \\ DateTime.utc_now()) do
    {today, _start, _seconds} = brasilia_day(now)

    Campaign
    |> where([c], c.status == :active and c.ends_on < ^today)
    |> Repo.all()
    |> Enum.map(&close_campaign(&1, now))
  end

  defp close_campaign(%Campaign{} = campaign, now) do
    delivered = delivered_total(campaign)
    undelivered = max(bought(campaign) - delivered, 0)
    refund = min(undelivered * campaign.cents_per_impression, campaign.paid_cents || 0)

    refunded =
      if refund > 0 and campaign.charge_txid do
        Pix.refund(campaign.charge_txid, refund, "devolucao-campanha-#{campaign.id}")
      else
        {:ok, nil}
      end

    with {:ok, e2e} <- refunded do
      campaign
      |> Ecto.Changeset.change(
        status: :ended,
        delivered: delivered,
        refunded_cents: if(e2e, do: refund, else: 0),
        refund_e2e_id: e2e,
        ended_at: DateTime.truncate(now, :second)
      )
      |> Repo.update()
    end
  end

  @doc """
  Apaga as exibições que já passaram do prazo. As impressões e views que
  vieram delas ficam, sem o vínculo.
  """
  def purge_slots(now \\ DateTime.utc_now()) do
    oldest = DateTime.add(now, -2 * @slot_ttl_seconds, :second)
    {count, _} = Repo.delete_all(from s in AdSlot, where: s.served_at < ^oldest)
    count
  end

  @doc """
  A campanha ainda pode entregar: está no ar, hoje está dentro das datas
  compradas e o total entregue não passou do que foi pago.
  """
  def deliverable(campaign_id, now \\ DateTime.utc_now()) do
    {today, _start, _seconds} = brasilia_day(now)

    case Repo.get(Campaign, campaign_id) do
      %Campaign{status: :active} = campaign ->
        within_dates =
          Date.compare(campaign.starts_on, today) != :gt and
            Date.compare(campaign.ends_on, today) != :lt

        if within_dates and delivered_total(campaign) < bought(campaign), do: campaign

      _ ->
        nil
    end
  end

  defp bought(%Campaign{} = campaign),
    do: daily_budget(campaign) * (Date.diff(campaign.ends_on, campaign.starts_on) + 1)

  defp delivered_total(%Campaign{id: id}) do
    Repo.aggregate(from(i in Impression, where: i.campaign_id == ^id), :count) +
      Repo.aggregate(from(v in AdView, where: v.campaign_id == ^id), :count)
  end

  defp shorts_ad_every do
    case Engine.transparency() do
      {:ok, %{"shorts_ad_every" => every}} when is_integer(every) and every > 0 -> every
      _ -> @default_ad_every
    end
  end

  @doc "Campanhas no ar hoje: aprovadas, pagas e dentro das datas compradas."
  def active_campaigns(today) do
    Campaign
    |> where([c], c.status == :active and c.starts_on <= ^today and c.ends_on >= ^today)
    |> order_by([c], asc: c.id)
    |> Repo.all()
  end

  @doc """
  Qual campanha entra em cada um dos próximos `slots` anúncios para esta
  pessoa. Quem decide é o motor, pelo ritmo do dia: cada campanha só pode ter
  mostrado a parte do dia que já passou, e o anúncio nacional não gasta numa
  cidade mais do que a parte dela na audiência. Sem motor, sem anúncio.
  """
  def pick_campaigns(viewer, slots, now \\ DateTime.utc_now())
  def pick_campaigns(_viewer, 0, _now), do: []

  def pick_campaigns(%Account{} = viewer, slots, now) do
    {today, day_start, seconds} = brasilia_day(now)
    campaigns = active_campaigns(today)
    region = viewer.region || ""

    if campaigns == [] do
      []
    else
      delivered = delivered_since(day_start, nil)
      in_region = delivered_since(day_start, region)

      request = %{
        viewer_region: region,
        seconds_into_day: seconds,
        audience: audience_since(day_start, region),
        slots: slots,
        candidates:
          Enum.map(campaigns, fn c ->
            %{
              id: c.id,
              scope: c.scope,
              region: c.region,
              daily_budget: daily_budget(c),
              delivered_today: Map.get(delivered, c.id, 0),
              delivered_in_region_today: Map.get(in_region, c.id, 0)
            }
          end)
      }

      case Engine.pick(request) do
        {:ok, %{"campaigns" => ids}} ->
          by_id = Map.new(campaigns, &{&1.id, &1})
          Enum.map(ids, &Map.fetch!(by_id, &1))

        _error ->
          []
      end
    end
  end

  defp daily_budget(%Campaign{impressions_per_day: per_day}) when is_integer(per_day), do: per_day
  # Campanhas antigas, de antes do preço tabelado: anúncio de 15 segundos.
  defp daily_budget(%Campaign{hours_per_day: hours}), do: div(hours * 3600, 15)

  @doc "O dia de Brasília de um instante: a data, quando começou e quantos segundos já passaram."
  def brasilia_day(now) do
    local = DateTime.add(now, @brasilia_offset, :second)
    today = DateTime.to_date(local)
    seconds = local.hour * 3600 + local.minute * 60 + local.second

    start =
      DateTime.add(DateTime.new!(today, ~T[00:00:00], "Etc/UTC"), -@brasilia_offset, :second)

    {today, start, seconds}
  end

  # Exibições de hoje por campanha, nos shorts e nos vídeos. Com `region`, só
  # as de gente daquela cidade.
  defp delivered_since(day_start, region) do
    shorts =
      from(i in Impression, where: i.inserted_at >= ^day_start, group_by: i.campaign_id)
      |> then(&if(region, do: where(&1, [i], i.viewer_region == ^region), else: &1))
      |> select([i], {i.campaign_id, count(i.id)})
      |> Repo.all()

    videos =
      from(v in AdView, where: v.inserted_at >= ^day_start, group_by: v.campaign_id)
      |> then(&if(region, do: where(&1, [v], v.viewer_region == ^region), else: &1))
      |> select([v], {v.campaign_id, count(v.id)})
      |> Repo.all()

    Map.merge(Map.new(shorts), Map.new(videos), fn _id, a, b -> a + b end)
  end

  # A parte da audiência de hoje (views de quem está logado) que é desta cidade.
  defp audience_since(day_start, region) do
    {in_region, total} =
      Repo.read().one(
        from v in View,
          join: a in Account,
          on: a.id == v.viewer_id,
          where: v.inserted_at >= ^day_start,
          select:
            {coalesce(sum(fragment("CASE WHEN ? = ? THEN 1 ELSE 0 END", a.region, ^region)), 0),
             count(v.id)}
      )

    %{region: in_region, total: total}
  end

  @doc """
  Registra que o anúncio dos shorts foi visto e divide a parte dos criadores
  entre os shorts do bloco, em partes iguais por short (params/ads.toml). Quem desligou anúncios, não
  pode receber ou é quem está assistindo fica fora do rateio, e a parte dele
  fica com o fundo. Com conta básica, sem gov.br, a parte dos criadores toda
  fica com o fundo.

  Cada exibição conta uma vez, só com os shorts que a rede mostrou antes
  dela, e o tempo assistido somado não passa do tempo que passou desde que a
  rede mostrou o bloco.
  """
  def record_impression(%Account{} = viewer, slot_id, watched, now \\ DateTime.utc_now())
      when is_list(watched) do
    now = DateTime.truncate(now, :second)

    with false <- Accounts.minor?(viewer),
         %AdSlot{used_at: nil} = slot <- open_slot(viewer, slot_id, :shorts, now),
         %Campaign{} = campaign <- deliverable(slot.campaign_id, now),
         breakdown when breakdown != [] <- breakdown(viewer, slot, watched, now),
         verified = Accounts.verified?(viewer),
         {:ok, splits, fund} <- split(campaign.cents_per_impression, breakdown, verified) do
      claim = from s in AdSlot, where: s.id == ^slot.id and is_nil(s.used_at)

      Multi.new()
      |> Multi.update_all(:slot, claim, set: [used_at: now])
      |> Multi.run(:unused, fn _repo, %{slot: {count, _}} ->
        if count == 1, do: {:ok, slot.id}, else: {:error, :already_counted}
      end)
      |> Multi.insert(:impression, %Impression{
        campaign_id: campaign.id,
        slot_id: slot.id,
        viewer_id: viewer.id,
        viewer_region: viewer.region,
        viewer_verified: verified,
        revenue_cents: campaign.cents_per_impression,
        fund_cents: fund,
        splits: splits,
        breakdown: breakdown
      })
      |> Repo.transaction()
      |> case do
        {:ok, %{impression: impression}} -> {:ok, impression}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      true -> {:error, :not_found}
      nil -> {:error, :not_found}
      %AdSlot{} -> {:error, :already_counted}
      [] -> {:error, :no_shorts}
      {:error, _reason} -> {:error, :engine_unavailable}
    end
  end

  # Um item por short do bloco, na ordem do id. O tempo de cada um vem do app,
  # mas só dos shorts do bloco, e a soma cabe no tempo desde a exibição.
  defp breakdown(viewer, slot, watched, now) do
    reported =
      for %{"post_id" => post_id, "watched_ms" => ms} <- watched,
          is_integer(post_id) and is_integer(ms) and post_id in slot.post_ids,
          into: %{},
          do: {post_id, ms |> max(0) |> min(600_000)}

    budget = DateTime.diff(now, slot.served_at, :millisecond) + @watch_slack_ms

    {items, _left} =
      slot.post_ids
      |> Social.get_posts()
      |> Enum.filter(&(&1.kind == :short))
      |> Enum.sort_by(& &1.id)
      |> Enum.map_reduce(budget, fn post, left ->
        ms = min(Map.get(reported, post.id, 0), max(left, 0))

        item = %{
          "post_id" => post.id,
          "author_id" => post.author_id,
          "watched_ms" => ms,
          "monetized" =>
            post.monetized and post.author_id != viewer.id and
              Accounts.can_monetize?(post.author)
        }

        {item, left - ms}
      end)

    items
  end

  # Sem gov.br, nada garante que é uma pessoa: a parte dos criadores fica com
  # o fundo, como no fechamento do mês.
  defp split(revenue_cents, _breakdown, false), do: {:ok, %{}, revenue_cents}

  # Os criadores viram números (1, 2, ...) na ordem do id, como no fechamento
  # do mês (ads-engine/src/closing.rs).
  defp split(revenue_cents, breakdown, true) do
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

    with {:ok, %{"cents_by_creator" => cents, "fund_cents" => fund}} <-
           Engine.split_shorts(revenue_cents, views) do
      {:ok, Map.new(cents, fn {number, value} -> {Map.fetch!(reverse, number), value} end), fund}
    end
  end

  ## Anúncio dentro do vídeo

  @doc """
  Um anúncio passou num vídeo, no ponto que o criador marcou. É isto que
  conta para o pagamento por faixas, depois das regras do antifraude no
  fechamento do mês.

  Só vale a exibição que a rede mostrou, num dos vídeos daquele feed, e cada
  ponto de cada vídeo conta uma vez por exibição.
  """
  def record_ad_view(%Account{} = viewer, slot_id, post_id, moment, now \\ DateTime.utc_now()) do
    post_id = to_integer(post_id)

    with false <- Accounts.minor?(viewer),
         %AdSlot{} = slot <- open_slot(viewer, slot_id, :video, now),
         true <- post_id in slot.post_ids,
         %Campaign{} = campaign <- deliverable(slot.campaign_id, now),
         %Post{kind: :video, monetized: true} = post <- Social.get_post(post_id, viewer),
         true <- moment in post.ad_markers,
         true <- post.author_id != viewer.id,
         true <- Accounts.can_monetize?(post.author) do
      verified = Accounts.verified?(viewer)

      %AdView{
        campaign_id: campaign.id,
        slot_id: slot.id,
        post_id: post.id,
        creator_id: post.author_id,
        viewer_id: viewer.id,
        viewer_region: viewer.region,
        viewer_verified: verified,
        regional: campaign.scope == :regional,
        moment: moment,
        revenue_cents: campaign.cents_per_impression
      }
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:slot_id, :post_id, :moment])
      |> case do
        {:ok, %AdView{id: nil}} ->
          {:error, :already_counted}

        {:ok, view} ->
          # A estimativa do mês no painel do criador. A conta de verdade sai
          # no fechamento, com o antifraude.
          if verified, do: Social.add_monthly_views(post.author_id, Social.current_month(), 1)
          {:ok, view}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  ## Painel do criador

  def dashboard(%Account{} = account) do
    month = Social.current_month()
    views = Social.monthly_views(account, month)

    with {:ok, payout} <- Engine.payout(views),
         {:ok, transparency} <- Engine.transparency() do
      bands = transparency["payout_bands"]
      key = Payments.pix_key(account)

      {:ok,
       %{
         month: month,
         monetizable: Accounts.can_monetize?(account),
         views: views,
         cents_per_thousand:
           get_in(transparency, ["ads_settings", "payout", "base_cents_per_thousand"]),
         effective_views: payout["effective_views"],
         payout_cents: payout["payout_cents"],
         params_version: payout["params_version"],
         bands: bands,
         current_band: current_band(bands, views),
         shorts: shorts_earnings(account, month),
         pix_key: key && %{kind: key.kind, hint: key.hint},
         company: company(account),
         statements:
           Enum.map(Payments.statements(account), fn %{payout: payout, month: closed} ->
             %{
               month: Calendar.strftime(closed.month, "%Y-%m"),
               total_cents: payout.total_cents,
               status: payout.status,
               paid_at: payout.paid_at
             }
           end)
       }}
    else
      {:error, _reason} -> {:error, :engine_unavailable}
    end
  end

  defp current_band(bands, views) do
    Enum.find_index(bands, fn band -> is_nil(band["up_to"]) or views <= band["up_to"] end)
  end

  @doc "A parte do criador nos anúncios dos shorts deste mês (estimativa até o fechamento)."
  def shorts_earnings(%Account{id: id}, month) do
    from = DateTime.new!(month, ~T[00:00:00], "Etc/UTC")

    query =
      from i in Impression,
        where: i.inserted_at >= ^from and fragment("(? ->> ?) IS NOT NULL", i.splits, ^id)

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

    %{total_cents: total, count: Repo.aggregate(query, :count), recent: recent}
  end

  ## Quem anuncia

  def advertiser(%Account{id: id}), do: Repo.get_by(Advertiser, account_id: id)

  defp company(account) do
    case advertiser(account) do
      nil -> nil
      company -> %{name: company.name, cnpj: CNPJ.format(company.cnpj)}
    end
  end

  @doc """
  Cadastra a empresa da conta: para anunciar ou para o criador receber como
  empresa. Em produção, o gov.br da empresa confirma que a pessoa responde
  pelo CNPJ; na demonstração, basta um CNPJ válido.
  """
  def register_advertiser(%Account{} = account, attrs) do
    name = attrs |> Map.get("name", "") |> to_string() |> String.trim()

    with true <- Accounts.verified?(account) || {:error, :not_verified},
         {:ok, cnpj} <- CNPJ.normalize(attrs["cnpj"]),
         true <- (name != "" and String.length(name) <= 80) || {:error, :invalid_name},
         nil <- advertiser(account) do
      %Advertiser{account_id: account.id, cnpj: cnpj, name: name}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:cnpj)
      |> Repo.insert()
      |> case do
        {:ok, advertiser} -> {:ok, advertiser}
        {:error, %Ecto.Changeset{}} -> {:error, :cnpj_taken}
      end
    else
      %Advertiser{} -> {:error, :already_advertiser}
      error -> error
    end
  end

  ## Compra de campanha

  @doc "O preço de uma campanha, pela tabela pública. Mesmo valor para todo anunciante."
  def price(attrs) do
    with {:ok, plan} <- campaign_plan(attrs),
         {:ok, quote} <- Engine.quote(plan.hours_per_day, plan.days, plan.scope == :regional) do
      {:ok, Map.merge(plan, %{quote: quote})}
    else
      {:error, {:status, 400, _}} -> {:error, :invalid_campaign}
      {:error, %{} = errors} -> {:error, errors}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _reason} -> {:error, :engine_unavailable}
    end
  end

  @doc """
  Cria a campanha. Ela vai para a moderação; aprovada, recebe a cobrança
  por PIX; paga, entra no ar nas datas compradas.
  """
  def create_campaign(%Account{} = account, attrs) do
    with %Advertiser{} = advertiser <- advertiser(account) || {:error, :not_advertiser},
         {:ok, %{quote: quote} = plan} <- price(attrs) do
      %Campaign{
        advertiser_id: advertiser.id,
        advertiser: advertiser.name,
        title: plan.title,
        body: plan.body,
        cta: plan.cta,
        color: plan.color,
        scope: plan.scope,
        region: plan.region,
        hours_per_day: plan.hours_per_day,
        impressions_per_day: quote["impressions_per_day"],
        cents_per_impression: quote["cents_per_impression"],
        price_cents: quote["total_cents"],
        paid_cents: 0,
        starts_on: plan.starts_on,
        ends_on: plan.ends_on,
        status: :in_review
      }
      |> Repo.insert()
    end
  end

  @fields ~w(title body cta color scope region hours_per_day starts_on ends_on)

  # Confere o que veio do formulário. Devolve os campos limpos e os dias.
  defp campaign_plan(attrs) do
    attrs = Map.take(attrs, @fields)

    text = fn key, max ->
      attrs |> Map.get(key, "") |> to_string() |> String.trim() |> String.slice(0, max)
    end

    scope = if attrs["scope"] == "regional", do: :regional, else: :national
    # O dia de Brasília, o mesmo da entrega.
    {today, _start, _seconds} = brasilia_day(DateTime.utc_now())

    plan = %{
      title: text.("title", 60),
      body: text.("body", 140),
      cta: text.("cta", 24),
      color: text.("color", 7),
      scope: scope,
      region: if(scope == :regional, do: text.("region", 60)),
      hours_per_day: to_integer(attrs["hours_per_day"]),
      starts_on: to_date(attrs["starts_on"]),
      ends_on: to_date(attrs["ends_on"])
    }

    errors =
      [
        {plan.title == "", :title, "Escreva o título do anúncio."},
        {not (plan.color =~ ~r/^#[0-9a-fA-F]{6}$/), :color, "Escolha uma cor."},
        {scope == :regional and not (plan.region =~ ~r|^.+/[A-Z]{2}$|), :region,
         "Diga a cidade, como Campinas/SP."},
        {not is_integer(plan.hours_per_day) or plan.hours_per_day < 1 or
           plan.hours_per_day > 100_000, :hours_per_day, "Entre 1 e 100 mil horas por dia."},
        {is_nil(plan.starts_on) or Date.before?(plan.starts_on, today), :starts_on,
         "A campanha começa hoje ou depois."},
        {is_nil(plan.ends_on) or (plan.starts_on && Date.before?(plan.ends_on, plan.starts_on)),
         :ends_on, "O fim vem depois do começo."},
        {plan.starts_on && plan.ends_on && Date.diff(plan.ends_on, plan.starts_on) >= 90,
         :ends_on, "No máximo 90 dias por campanha."}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Map.new(fn {_bad, field, message} -> {field, [message]} end)

    if errors == %{},
      do: {:ok, Map.put(plan, :days, Date.diff(plan.ends_on, plan.starts_on) + 1)},
      else: {:error, errors}
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp to_integer(_value), do: nil

  defp to_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp to_date(_value), do: nil

  def campaigns(%Advertiser{id: id}) do
    Repo.all(from c in Campaign, where: c.advertiser_id == ^id, order_by: [desc: c.id])
  end

  def pending_campaigns do
    Repo.all(from c in Campaign, where: c.status == :in_review, order_by: [asc: c.id])
  end

  @doc """
  A moderação aprova (e a rede gera a cobrança por PIX) ou recusa citando uma
  das regras de anúncio. Quem cria a campanha não aprova a própria.
  """
  def review(
        %Account{moderator: true} = moderator,
        %Campaign{status: :in_review} = campaign,
        decision
      ) do
    advertiser = campaign.advertiser_id && Repo.get(Advertiser, campaign.advertiser_id)

    cond do
      advertiser && advertiser.account_id == moderator.id ->
        {:error, :own_campaign}

      decision == :approve ->
        decide(campaign, fn locked ->
          txid = "campanha#{locked.id}" <> random_txid(12)

          with {:ok, brcode} <-
                 Pix.create_charge(locked.price_cents, txid, "Campanha #{locked.id}") do
            [
              status: :awaiting_payment,
              charge_txid: txid,
              brcode: brcode,
              reviewed_by_id: moderator.id,
              reviewed_at: now()
            ]
          end
        end)

      match?({:reject, _}, decision) and Rules.get(elem(decision, 1)) ->
        decide(campaign, fn _locked ->
          [
            status: :rejected,
            rejection_rule: elem(decision, 1),
            reviewed_by_id: moderator.id,
            reviewed_at: now()
          ]
        end)

      true ->
        {:error, :invalid_rule}
    end
  end

  def review(%Account{moderator: true}, %Campaign{}, _decision), do: {:error, :already_reviewed}
  def review(_account, _campaign, _decision), do: {:error, :not_found}

  # Trava a campanha e decide só se ela ainda espera análise: duas pessoas da
  # moderação nunca geram duas cobranças para a mesma campanha.
  defp decide(%Campaign{id: id}, changes) do
    Repo.transaction(fn ->
      locked =
        Repo.one(
          from c in Campaign, where: c.id == ^id and c.status == :in_review, lock: "FOR UPDATE"
        )

      with %Campaign{} <- locked || {:error, :already_reviewed},
           fields when is_list(fields) <- changes.(locked),
           {:ok, updated} <- locked |> Ecto.Changeset.change(fields) |> Repo.update() do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  O banco avisou que a cobrança foi paga. Só vale o valor exato da
  cobrança; a campanha entra no ar nas datas compradas.
  """
  def confirm_payment(txid, cents) do
    case Repo.get_by(Campaign, charge_txid: txid) do
      %Campaign{status: :awaiting_payment, price_cents: ^cents} = campaign ->
        campaign
        |> Ecto.Changeset.change(status: :active, paid_cents: cents, paid_at: now())
        |> Repo.update()

      %Campaign{status: :active} = campaign ->
        {:ok, campaign}

      _ ->
        {:error, :not_found}
    end
  end

  defp random_txid(size) do
    :crypto.strong_rand_bytes(size) |> Base.encode32(padding: false) |> binary_part(0, size)
  end

  ## Biblioteca pública de anúncios

  @doc "Toda campanha paga: quem pagou (com CNPJ), quanto, onde, quando, e quanto já foi entregue."
  def library do
    delivered =
      Map.merge(
        Map.new(
          Repo.all(
            from i in Impression, group_by: i.campaign_id, select: {i.campaign_id, count(i.id)}
          )
        ),
        Map.new(
          Repo.all(
            from v in AdView, group_by: v.campaign_id, select: {v.campaign_id, count(v.id)}
          )
        ),
        fn _id, a, b -> a + b end
      )

    Campaign
    |> where([c], c.status == :active)
    |> order_by([c], asc: c.scope, asc: c.advertiser)
    |> preload(:advertiser_record)
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :delivered, Map.get(delivered, &1.id, 0)))
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
