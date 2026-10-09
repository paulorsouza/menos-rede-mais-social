defmodule RedeSocial.AdsTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Ads, Engine}
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Ads.Campaign

  describe "pick_campaign/3" do
    setup do
      %{
        national: %Campaign{id: 1, scope: :national},
        local: %Campaign{id: 2, scope: :regional, region: "Campinas/SP"},
        elsewhere: %Campaign{id: 3, scope: :regional, region: "Recife/PE"}
      }
    end

    test "quem tem anúncio da própria cidade vê regional e nacional alternados", c do
      campaigns = [c.national, c.local, c.elsewhere]
      viewer = %Account{region: "Campinas/SP"}

      assert Ads.pick_campaign(campaigns, viewer, 0) == c.local
      assert Ads.pick_campaign(campaigns, viewer, 1) == c.national
      assert Ads.pick_campaign(campaigns, viewer, 2) == c.local
    end

    test "quem não tem anúncio da própria cidade vê o nacional", c do
      campaigns = [c.national, c.local, c.elsewhere]
      assert Ads.pick_campaign(campaigns, %Account{region: "Manaus/AM"}, 0) == c.national
    end
  end

  describe "record_impression/3" do
    test "o motor divide a receita e cada criador recebe a sua parte" do
      big = account_fixture(govbr_level: :ouro)
      bronze = account_fixture(govbr_level: :bronze)
      first = short_fixture(big)
      second = short_fixture(bronze)

      campaign =
        Repo.insert!(%Campaign{
          advertiser: "Anunciante de Teste",
          title: "Teste",
          scope: :national,
          hours_per_day: 1,
          cents_per_impression: 3,
          paid_cents: 0,
          starts_on: ~D[2026-01-01],
          ends_on: ~D[2027-12-31]
        })

      test_pid = self()

      Req.Test.stub(Engine, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)
        send(test_pid, {:engine_request, request})
        paid = Enum.find(request["views"], & &1["monetized"])
        Req.Test.json(conn, %{"cents_by_creator" => %{to_string(paid["creator_id"]) => 3}})
      end)

      watched = [
        %{"post_id" => first.id, "watched_ms" => 8_000},
        %{"post_id" => second.id, "watched_ms" => 8_000}
      ]

      {:ok, impression} = Ads.record_impression(account_fixture(), campaign.id, watched)

      assert_received {:engine_request, %{"revenue_cents" => 3, "views" => views}}
      # Conta bronze não pode receber, então vai para o motor como não monetizada.
      assert views |> Enum.map(& &1["monetized"]) |> Enum.sort() == [false, true]

      assert impression.splits == %{big.id => 3}
      assert Ads.shorts_earnings(big).total_cents == 3
      assert Ads.shorts_earnings(bronze).total_cents == 0
    end
  end
end
