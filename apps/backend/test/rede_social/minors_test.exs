defmodule RedeSocial.MinorsTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Accounts, Ads, Social}
  alias RedeSocial.Ads.Campaign

  setup do
    minor = account_fixture(age_band: :minor, govbr_level: :prata)
    %{minor: minor, post: post_fixture(minor, body: "Meu desenho novo")}
  end

  describe "perfil privado" do
    test "só o próprio menor e quem ele segue veem os posts", %{minor: minor, post: post} do
      stranger = account_fixture()
      friend = account_fixture()
      {:ok, true} = Social.toggle_follow(minor, friend)
      # Seguir um menor não basta: ele precisa seguir de volta.
      {:ok, true} = Social.toggle_follow(stranger, minor)

      assert Social.get_post(post.id, nil) == nil
      assert Social.get_post(post.id, stranger) == nil
      assert Social.get_post(post.id, friend)
      assert Social.get_post(post.id, minor)

      assert Social.list_author_posts(minor, stranger) == []
      assert [_post] = Social.list_author_posts(minor, friend)
      refute Social.can_see_posts?(minor, stranger)
      assert Social.can_see_posts?(minor, friend)
    end

    test "nunca vira sugestão para quem o menor não segue", %{minor: minor, post: post} do
      friend = account_fixture()
      {:ok, true} = Social.toggle_follow(minor, friend)
      candidates = fn viewer -> Enum.map(Social.candidates(viewer, [:text], 50), & &1.id) end

      refute post.id in candidates.(account_fixture())
      assert post.id in candidates.(friend)
    end

    test "posts de adultos continuam abertos para todo mundo" do
      post = post_fixture(account_fixture())
      assert Social.get_post(post.id, nil)
    end
  end

  describe "anúncios" do
    test "menor não recebe por anúncio, mesmo com gov.br prata", %{minor: minor} do
      refute Accounts.can_monetize?(minor)
      assert Accounts.can_monetize?(account_fixture(govbr_level: :prata))
    end

    test "menor não vê anúncio entre os shorts" do
      Repo.insert!(%Campaign{
        advertiser: "Anunciante de Teste",
        title: "Teste",
        scope: :national,
        hours_per_day: 1,
        cents_per_impression: 3,
        paid_cents: 0,
        starts_on: ~D[2026-01-01],
        ends_on: ~D[2030-12-31]
      })

      creator = account_fixture(govbr_level: :ouro)
      for _ <- 1..6, do: short_fixture(creator)

      RedeSocial.EngineStub.stub()

      ads = fn viewer ->
        {:ok, feed} = Ads.shorts_feed(viewer, "public_ranking")
        Enum.count(feed.items, &match?({:ad, _campaign, _ids, _slot}, &1))
      end

      assert ads.(account_fixture()) == 1
      assert ads.(account_fixture(age_band: :minor)) == 0
    end
  end
end
