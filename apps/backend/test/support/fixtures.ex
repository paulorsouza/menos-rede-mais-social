defmodule RedeSocial.Fixtures do
  @moduledoc "Contas e posts para os testes."

  alias RedeSocial.{Accounts, Repo}
  alias RedeSocial.Accounts.CPF
  alias RedeSocial.Social.Post

  def account_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        nickname: "pessoa#{System.unique_integer([:positive])}",
        govbr_level: :prata,
        age_band: :adult,
        region: "Campinas/SP"
      })

    {:ok, account} = Accounts.register_verified(attrs, CPF.generate_for_testing())
    account
  end

  def moderator_fixture do
    {:ok, moderator} = RedeSocial.Moderation.grant_moderator(account_fixture())
    moderator
  end

  def post_fixture(author, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{kind: :text, body: "Um post de teste"})
    {media_path, attrs} = Map.pop(attrs, :media_path)

    %Post{author_id: author.id, media_path: media_path}
    |> Post.changeset(attrs)
    |> Repo.insert!()
    |> Repo.preload(:author)
  end

  def campaign_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        advertiser: "Anunciante de Teste",
        title: "Teste",
        scope: :national,
        hours_per_day: 1,
        impressions_per_day: 240,
        cents_per_impression: 3,
        paid_cents: 0,
        status: :active,
        starts_on: Date.add(Date.utc_today(), -30),
        ends_on: Date.add(Date.utc_today(), 30)
      })

    Repo.insert!(struct(RedeSocial.Ads.Campaign, attrs))
  end

  def video_fixture(author, attrs \\ %{}) do
    post_fixture(
      author,
      Enum.into(attrs, %{
        kind: :video,
        media_path: "/media/v/teste/master.m3u8",
        ad_markers: ["start", "end"]
      })
    )
  end

  def short_fixture(author, attrs \\ %{}) do
    post_fixture(
      author,
      Enum.into(attrs, %{kind: :short, media_path: "/uploads/teste.mp4", monetized: true})
    )
  end
end
