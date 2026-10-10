defmodule RedeSocial.AdsTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Ads, EngineStub, Moderation, Repo, Social}
  alias RedeSocial.Accounts.CNPJ
  alias RedeSocial.Ads.{AdView, Impression}
  alias RedeSocial.Payments.BRCode

  describe "escolha da campanha" do
    test "o motor recebe as campanhas no ar com o que cada uma já entregou hoje" do
      test_pid = self()
      national = campaign_fixture(impressions_per_day: 1000)
      local = campaign_fixture(scope: :regional, region: "Campinas/SP", impressions_per_day: 50)
      _paused = campaign_fixture(status: :awaiting_payment)
      _over = campaign_fixture(ends_on: Date.add(Date.utc_today(), -1))

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
        Enum.count(feed.items, &match?({:ad, _campaign, _ids}, &1))
      end

      assert ads.(account_fixture()) == 1
      assert ads.(account_fixture(age_band: :minor)) == 0
    end
  end

  describe "anúncio dos shorts" do
    test "a parte dos criadores vai pelo tempo assistido e o resto fica com o fundo" do
      big = account_fixture(govbr_level: :ouro)
      bronze = account_fixture(govbr_level: :bronze)
      first = short_fixture(big)
      second = short_fixture(bronze)
      campaign = campaign_fixture(cents_per_impression: 10)
      EngineStub.stub()

      watched = [
        %{"post_id" => first.id, "watched_ms" => 8_000},
        %{"post_id" => second.id, "watched_ms" => 8_000}
      ]

      viewer = account_fixture(region: "Recife/PE")
      {:ok, impression} = Ads.record_impression(viewer, campaign.id, watched)

      # 55% para os criadores, e a conta bronze não recebe: a parte dela
      # também fica com o fundo.
      assert impression.splits == %{big.id => 5}
      assert impression.fund_cents == 5
      assert impression.viewer_region == "Recife/PE"
      assert Ads.shorts_earnings(big, Social.current_month()).total_cents == 5
    end

    test "campanha que ainda não foi paga não entra" do
      campaign = campaign_fixture(status: :awaiting_payment)
      short = short_fixture(account_fixture(govbr_level: :ouro))
      EngineStub.stub()

      assert Ads.record_impression(account_fixture(), campaign.id, [
               %{"post_id" => short.id, "watched_ms" => 1000}
             ]) == {:error, :not_found}
    end
  end

  describe "anúncio dentro do vídeo" do
    setup do
      creator = account_fixture(govbr_level: :prata)
      %{creator: creator, video: video_fixture(creator), campaign: campaign_fixture()}
    end

    test "conta no ponto que o criador marcou e entra na estimativa do mês", c do
      viewer = account_fixture()

      assert {:ok, %AdView{} = view} =
               Ads.record_ad_view(viewer, c.campaign.id, c.video.id, "start")

      assert view.creator_id == c.creator.id
      assert view.viewer_verified
      assert view.revenue_cents == 3
      assert Social.monthly_views(c.creator) == 1
    end

    test "fora do ponto marcado, no próprio vídeo ou para menor, não conta", c do
      assert Ads.record_ad_view(account_fixture(), c.campaign.id, c.video.id, "middle") ==
               {:error, :not_found}

      assert Ads.record_ad_view(c.creator, c.campaign.id, c.video.id, "start") ==
               {:error, :not_found}

      assert Ads.record_ad_view(
               account_fixture(age_band: :minor),
               c.campaign.id,
               c.video.id,
               "start"
             ) ==
               {:error, :not_found}

      assert Repo.aggregate(AdView, :count) == 0
    end

    test "conta básica fica registrada, mas não entra na estimativa", c do
      {:ok, basic} = RedeSocial.Accounts.register_basic(%{nickname: "so_assiste_video"})

      assert {:ok, %AdView{viewer_verified: false}} =
               Ads.record_ad_view(basic, c.campaign.id, c.video.id, "start")

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
          "starts_on" => Date.to_iso8601(Date.utc_today()),
          "ends_on" => Date.to_iso8601(Date.add(Date.utc_today(), 9))
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
