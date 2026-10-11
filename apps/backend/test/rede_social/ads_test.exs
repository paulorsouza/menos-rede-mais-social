defmodule RedeSocial.AdsTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Ads, EngineStub, Moderation, Repo, Social}
  alias RedeSocial.Accounts.CNPJ
  alias RedeSocial.Ads.{AdSlot, AdView, Impression}
  alias RedeSocial.Payments.BRCode

  # O dia de Brasília, o mesmo que o código usa para datas de campanha.
  defp today, do: elem(Ads.brasilia_day(DateTime.utc_now()), 0)

  describe "escolha da campanha" do
    test "o motor recebe as campanhas no ar com o que cada uma já entregou hoje" do
      test_pid = self()
      national = campaign_fixture(impressions_per_day: 1000)
      local = campaign_fixture(scope: :regional, region: "Campinas/SP", impressions_per_day: 50)
      _paused = campaign_fixture(status: :awaiting_payment)
      _over = campaign_fixture(ends_on: Date.add(today(), -1))

      viewer = account_fixture(region: "Campinas/SP")

      Repo.insert!(%Impression{
        campaign_id: local.id,
        revenue_cents: 1,
        viewer_region: "Campinas/SP"
      })

      EngineStub.stub(%{
        "/ads/pick" => fn request ->
          send(test_pid, {:pick, request})
          %{"campaigns" => [local.id, national.id]}
        end
      })

      assert Enum.map(Ads.pick_campaigns(viewer, 2), & &1.id) == [local.id, national.id]

      assert_received {:pick, request}
      assert request["viewer_region"] == "Campinas/SP"
      assert request["slots"] == 2

      assert Enum.map(request["candidates"], & &1["id"]) |> Enum.sort() ==
               Enum.sort([national.id, local.id])

      delivered = Map.new(request["candidates"], &{&1["id"], &1["delivered_today"]})
      assert delivered[local.id] == 1
      assert delivered[national.id] == 0
    end

    test "menor de idade não vê anúncio nos shorts" do
      campaign_fixture()
      creator = account_fixture(govbr_level: :ouro)
      for _ <- 1..6, do: short_fixture(creator)
      EngineStub.stub()

      ads = fn viewer ->
        {:ok, feed} = Ads.shorts_feed(viewer, "public_ranking")
        Enum.count(feed.items, &match?({:ad, _campaign, _ids, _slot}, &1))
      end

      assert ads.(account_fixture()) == 1
      assert ads.(account_fixture(age_band: :minor)) == 0
    end
  end

  # Uma exibição que a rede mostrou, um minuto atrás.
  defp slot(viewer, campaign, kind, posts, served_at \\ DateTime.add(DateTime.utc_now(), -60)) do
    Repo.insert!(%AdSlot{
      viewer_id: viewer.id,
      campaign_id: campaign.id,
      kind: kind,
      post_ids: Enum.map(posts, & &1.id),
      served_at: DateTime.truncate(served_at, :second)
    })
  end

  defp watched(posts, ms), do: Enum.map(posts, &%{"post_id" => &1.id, "watched_ms" => ms})

  describe "anúncio dos shorts" do
    setup do
      EngineStub.stub()
      :ok
    end

    test "a parte dos criadores vai pelo tempo assistido e o resto fica com o fundo" do
      big = account_fixture(govbr_level: :ouro)
      bronze = account_fixture(govbr_level: :bronze)
      posts = [short_fixture(big), short_fixture(bronze)]
      campaign = campaign_fixture(cents_per_impression: 10)

      viewer = account_fixture(region: "Recife/PE")
      slot = slot(viewer, campaign, :shorts, posts)
      {:ok, impression} = Ads.record_impression(viewer, slot.id, watched(posts, 8_000))

      # 55% para os criadores, e a conta bronze não recebe: a parte dela
      # também fica com o fundo.
      assert impression.splits == %{big.id => 5}
      assert impression.fund_cents == 5
      assert impression.viewer_region == "Recife/PE"
      assert impression.viewer_verified
      assert Ads.shorts_earnings(big, Social.current_month()).total_cents == 5
    end

    test "o feed devolve a exibição, que conta uma vez só e só para quem viu" do
      campaign_fixture()
      creator = account_fixture(govbr_level: :ouro)
      for _ <- 1..6, do: short_fixture(creator)
      viewer = account_fixture()

      {:ok, feed} = Ads.shorts_feed(viewer, "public_ranking")
      [{:ad, _campaign, ids, slot_id}] = Enum.filter(feed.items, &(elem(&1, 0) == :ad))
      watched = Enum.map(ids, &%{"post_id" => &1, "watched_ms" => 0})

      assert Ads.record_impression(account_fixture(), slot_id, watched) == {:error, :not_found}
      assert {:ok, %Impression{}} = Ads.record_impression(viewer, slot_id, watched)
      assert Ads.record_impression(viewer, slot_id, watched) == {:error, :already_counted}
      assert Repo.aggregate(Impression, :count) == 1
    end

    test "só os shorts da exibição contam, e o tempo cabe no que passou desde ela" do
      creator = account_fixture(govbr_level: :ouro)
      [first, second] = posts = [short_fixture(creator), short_fixture(creator)]
      other = short_fixture(account_fixture(govbr_level: :ouro))
      campaign = campaign_fixture()
      viewer = account_fixture()

      # Mostrada há 20 segundos: 600 segundos em cada short não cabem.
      served = DateTime.add(DateTime.utc_now(), -20)
      slot = slot(viewer, campaign, :shorts, posts, served)

      {:ok, impression} =
        Ads.record_impression(viewer, slot.id, watched([first, second, other], 600_000))

      assert Enum.map(impression.breakdown, & &1["post_id"]) == [first.id, second.id]
      assert impression.breakdown |> Enum.map(& &1["watched_ms"]) |> Enum.sum() <= 26_000
    end

    test "o próprio short não paga quem assiste" do
      creator = account_fixture(govbr_level: :ouro)
      posts = [short_fixture(creator)]
      campaign = campaign_fixture(cents_per_impression: 10)
      slot = slot(creator, campaign, :shorts, posts)

      {:ok, impression} = Ads.record_impression(creator, slot.id, watched(posts, 5_000))

      assert impression.splits == %{}
      assert impression.fund_cents == 10
    end

    test "com conta básica, a parte dos criadores fica com o fundo" do
      posts = [short_fixture(account_fixture(govbr_level: :ouro))]
      campaign = campaign_fixture(cents_per_impression: 10)
      {:ok, basic} = RedeSocial.Accounts.register_basic(%{nickname: "so_assiste_short"})
      slot = slot(basic, campaign, :shorts, posts)

      {:ok, impression} = Ads.record_impression(basic, slot.id, watched(posts, 5_000))

      refute impression.viewer_verified
      assert impression.splits == %{}
      assert impression.fund_cents == 10
    end

    test "campanha sem pagamento, fora das datas ou já entregue não conta" do
      posts = [short_fixture(account_fixture(govbr_level: :ouro))]
      viewer = account_fixture()
      yesterday = Date.add(today(), -2)

      for campaign <- [
            campaign_fixture(status: :awaiting_payment),
            campaign_fixture(starts_on: Date.add(yesterday, -5), ends_on: yesterday),
            campaign_fixture(impressions_per_day: 0)
          ] do
        slot = slot(viewer, campaign, :shorts, posts)

        assert Ads.record_impression(viewer, slot.id, watched(posts, 1_000)) ==
                 {:error, :not_found}
      end
    end

    test "exibições vencidas são apagadas, e a impressão fica" do
      posts = [short_fixture(account_fixture(govbr_level: :ouro))]
      viewer = account_fixture()
      campaign = campaign_fixture()
      used = slot(viewer, campaign, :shorts, posts)
      {:ok, impression} = Ads.record_impression(viewer, used.id, watched(posts, 1_000))
      _fresh = slot(viewer, campaign, :shorts, posts)

      assert Ads.purge_slots(DateTime.add(DateTime.utc_now(), 7 * 3600)) == 2
      assert Repo.reload!(impression).slot_id == nil
    end

    test "exibição velha não conta" do
      posts = [short_fixture(account_fixture(govbr_level: :ouro))]
      viewer = account_fixture()

      old =
        slot(
          viewer,
          campaign_fixture(),
          :shorts,
          posts,
          DateTime.add(DateTime.utc_now(), -4 * 3600)
        )

      assert Ads.record_impression(viewer, old.id, watched(posts, 1_000)) == {:error, :not_found}
    end
  end

  describe "anúncio dentro do vídeo" do
    setup do
      EngineStub.stub()
      creator = account_fixture(govbr_level: :prata)
      video = video_fixture(creator)
      %{creator: creator, video: video, campaign: campaign_fixture()}
    end

    test "conta no ponto que o criador marcou e entra na estimativa do mês", c do
      viewer = account_fixture()
      slot = slot(viewer, c.campaign, :video, [c.video])

      assert {:ok, %AdView{} = view} = Ads.record_ad_view(viewer, slot.id, c.video.id, "start")

      assert view.creator_id == c.creator.id
      assert view.viewer_verified
      assert view.revenue_cents == 3
      assert Social.monthly_views(c.creator) == 1

      # O mesmo ponto, na mesma exibição, não conta de novo.
      assert Ads.record_ad_view(viewer, slot.id, c.video.id, "start") ==
               {:error, :already_counted}

      assert {:ok, %AdView{}} = Ads.record_ad_view(viewer, slot.id, c.video.id, "end")
      assert Social.monthly_views(c.creator) == 2
    end

    test "o feed de vídeos traz a exibição, que vale só para os vídeos dele", c do
      viewer = account_fixture()
      {campaign, slot} = Ads.video_ad(viewer, [c.video.id])
      assert campaign.id == c.campaign.id

      other = video_fixture(c.creator)
      assert Ads.record_ad_view(viewer, slot.id, other.id, "start") == {:error, :not_found}
      assert {:ok, %AdView{}} = Ads.record_ad_view(viewer, slot.id, c.video.id, "start")
      assert Ads.video_ad(account_fixture(age_band: :minor), [c.video.id]) == nil
    end

    test "fora do ponto marcado, no próprio vídeo, para menor ou sem exibição, não conta", c do
      viewer = account_fixture()
      minor = account_fixture(age_band: :minor)

      assert Ads.record_ad_view(
               viewer,
               slot(viewer, c.campaign, :video, [c.video]).id,
               c.video.id,
               "middle"
             ) ==
               {:error, :not_found}

      assert Ads.record_ad_view(
               c.creator,
               slot(c.creator, c.campaign, :video, [c.video]).id,
               c.video.id,
               "start"
             ) ==
               {:error, :not_found}

      assert Ads.record_ad_view(
               minor,
               slot(minor, c.campaign, :video, [c.video]).id,
               c.video.id,
               "start"
             ) ==
               {:error, :not_found}

      assert Ads.record_ad_view(viewer, nil, c.video.id, "start") == {:error, :not_found}

      # A exibição dos shorts não vale para o vídeo.
      assert Ads.record_ad_view(
               viewer,
               slot(viewer, c.campaign, :shorts, [c.video]).id,
               c.video.id,
               "start"
             ) ==
               {:error, :not_found}

      assert Repo.aggregate(AdView, :count) == 0
    end

    test "conta básica fica registrada, mas não entra na estimativa", c do
      {:ok, basic} = RedeSocial.Accounts.register_basic(%{nickname: "so_assiste_video"})
      slot = slot(basic, c.campaign, :video, [c.video])

      assert {:ok, %AdView{viewer_verified: false}} =
               Ads.record_ad_view(basic, slot.id, c.video.id, "start")

      assert Social.monthly_views(c.creator) == 0
    end
  end

  describe "compra de campanha" do
    setup do
      EngineStub.stub()
      buyer = account_fixture()

      {:ok, advertiser} =
        Ads.register_advertiser(buyer, %{
          "cnpj" => CNPJ.generate_for_testing(),
          "name" => "Padaria Teste"
        })

      %{buyer: buyer, advertiser: advertiser}
    end

    defp attrs(overrides \\ %{}) do
      Map.merge(
        %{
          "title" => "Pão quentinho",
          "body" => "Toda manhã",
          "cta" => "Ver",
          "color" => "#c2410c",
          "scope" => "regional",
          "region" => "Campinas/SP",
          "hours_per_day" => "2",
          "starts_on" => Date.to_iso8601(today()),
          "ends_on" => Date.to_iso8601(Date.add(today(), 9))
        },
        overrides
      )
    end

    test "o preço sai da tabela pública: exibições por dia vezes dias vezes preço", c do
      {:ok, campaign} = Ads.create_campaign(c.buyer, attrs())

      assert campaign.status == :in_review
      assert campaign.impressions_per_day == 480
      assert campaign.price_cents == 480 * 10 * 1
      assert campaign.advertiser == "Padaria Teste"
    end

    test "aprovada, ganha cobrança PIX; paga no valor certo, entra no ar", c do
      {:ok, campaign} = Ads.create_campaign(c.buyer, attrs())
      moderator = moderator_fixture()

      {:ok, approved} = Ads.review(moderator, campaign, :approve)
      assert approved.status == :awaiting_payment
      assert {:ok, fields} = BRCode.parse(approved.brcode)
      assert fields["54"] == "48.00"
      assert fields["62"] =~ approved.charge_txid

      assert Ads.confirm_payment(approved.charge_txid, 100) == {:error, :not_found}
      {:ok, active} = Ads.confirm_payment(approved.charge_txid, approved.price_cents)
      assert active.status == :active
      assert active.paid_cents == 4800

      # A segunda aprovação não gera outra cobrança.
      assert Ads.review(moderator_fixture(), campaign, :approve) == {:error, :already_reviewed}
      assert Repo.reload!(active).charge_txid == approved.charge_txid
    end

    test "recusada cita uma regra de anúncio; quem anuncia não aprova a própria", c do
      {:ok, campaign} = Ads.create_campaign(c.buyer, attrs())
      {:ok, own_moderator} = Moderation.grant_moderator(c.buyer)

      assert Ads.review(own_moderator, campaign, :approve) == {:error, :own_campaign}

      {:ok, rejected} = Ads.review(moderator_fixture(), campaign, {:reject, 1})
      assert rejected.status == :rejected
      assert rejected.rejection_rule == 1

      assert Ads.review(moderator_fixture(), Repo.reload!(rejected), :approve) ==
               {:error, :already_reviewed}
    end

    test "datas e campos errados voltam com o motivo", c do
      assert {:error, errors} =
               Ads.create_campaign(
                 c.buyer,
                 attrs(%{"region" => "Campinas", "ends_on" => "2000-01-01"})
               )

      assert Map.keys(errors) |> Enum.sort() == [:ends_on, :region]
    end

    test "CNPJ inválido ou repetido não anuncia", c do
      assert Ads.register_advertiser(account_fixture(), %{
               "cnpj" => "11.111.111/1111-11",
               "name" => "X"
             }) ==
               {:error, :invalid_cnpj}

      assert Ads.register_advertiser(account_fixture(), %{
               "cnpj" => c.advertiser.cnpj,
               "name" => "Y"
             }) ==
               {:error, :cnpj_taken}
    end
  end

  describe "encerramento" do
    test "a campanha que acabou devolve por PIX o que não foi entregue" do
      yesterday = Date.add(today(), -1)

      campaign =
        campaign_fixture(
          impressions_per_day: 10,
          cents_per_impression: 3,
          paid_cents: 60,
          charge_txid: "campanha-teste",
          starts_on: Date.add(yesterday, -1),
          ends_on: yesterday
        )

      for _ <- 1..4, do: Repo.insert!(%Impression{campaign_id: campaign.id, revenue_cents: 3})
      running = campaign_fixture()

      assert [{:ok, ended}] = Ads.close_ended_campaigns()

      # Comprou 20 exibições, entregou 4: as outras 16 voltam, a 3 centavos.
      assert ended.id == campaign.id
      assert ended.status == :ended
      assert ended.delivered == 4
      assert ended.refunded_cents == 48
      assert ended.refund_e2e_id =~ ~r/^D/
      assert Repo.reload!(running).status == :active

      # Encerrada, não entra de novo nem entrega mais.
      assert Ads.close_ended_campaigns() == []
      assert Ads.deliverable(campaign.id) == nil
    end
  end

  describe "biblioteca" do
    test "mostra só campanha paga, com o que já foi entregue" do
      paid = campaign_fixture()
      _unpaid = campaign_fixture(status: :awaiting_payment)
      Repo.insert!(%Impression{campaign_id: paid.id, revenue_cents: 3})

      assert [%{id: id, delivered: 1}] = Ads.library()
      assert id == paid.id
    end
  end
end
