defmodule RedeSocialWeb.Present do
  @moduledoc """
  Como contas, posts e anúncios aparecem no JSON da API. O perfil público
  nunca leva o nível do gov.br nem nada que identifique a pessoa: só apelido,
  selo, região e bio.
  """

  alias RedeSocial.{Accounts, Moderation, Social}
  alias RedeSocial.Moderation.Rules

  def account(nil), do: nil

  def account(account) do
    %{
      id: account.id,
      nickname: account.nickname,
      bio: account.bio,
      region: account.region,
      verified: Accounts.verified?(account)
    }
  end

  @doc "A própria conta, com o que só a dona dela precisa ver."
  def me(nil), do: nil

  def me(account) do
    account
    |> account()
    |> Map.merge(%{
      govbr_level: account.govbr_level,
      can_publish: Accounts.verified?(account),
      can_monetize: Accounts.can_monetize?(account),
      moderator: account.moderator,
      legal_officer: account.legal_officer,
      unread_notices: Moderation.unread_count(account)
    })
  end

  def rule(nil), do: nil
  def rule(number), do: Rules.get(number)

  @doc "Aviso da moderação para o autor, com o post e o que dá para fazer."
  def notice(notice) do
    post = notice.post
    status = post && Moderation.appeal_status(post)

    %{
      id: notice.id,
      kind: notice.kind,
      rule: rule(notice.rule),
      created_at: notice.inserted_at,
      read: notice.read_at != nil,
      post: post && post(post),
      appeal: status,
      can_appeal:
        notice.kind == "removed" and post != nil and post.removed_at != nil and status == nil
    }
  end

  @doc "Um post na fila de denúncias."
  def queue_entry(entry) do
    %{
      post: post(entry.post),
      total: entry.total,
      since: entry.since,
      reports: Enum.map(entry.reports, &Map.put(&1, :title, Rules.get(&1.rule).title))
    }
  end

  @doc "Um recurso esperando decisão."
  def appeal(appeal) do
    %{
      id: appeal.id,
      text: appeal.text,
      created_at: appeal.inserted_at,
      rule: rule(appeal.post.removal_rule),
      removed_by: account(appeal.post.removed_by),
      post: post(appeal.post)
    }
  end

  def entry(%{post: post, stats: stats, reasons: reasons}), do: post(post, stats, reasons)

  def post(post, stats \\ Social.empty_stats(), reasons \\ []) do
    %{
      id: post.id,
      kind: post.kind,
      body: post.body,
      media_url: post.media_path,
      alt_text: post.alt_text,
      monetized: post.monetized,
      ad_markers: post.ad_markers,
      created_at: post.inserted_at,
      author: account(post.author),
      likes: stats.likes,
      saves: stats.saves,
      views: stats.views,
      liked: stats.liked,
      saved: stats.saved,
      reasons: reasons
    }
  end

  def campaign(campaign) do
    %{
      id: campaign.id,
      advertiser: campaign.advertiser,
      title: campaign.title,
      body: campaign.body,
      cta: campaign.cta,
      color: campaign.color,
      scope: campaign.scope,
      region: campaign.region
    }
  end

  @doc "Para a biblioteca pública de anúncios: inclui período, horas e valor pago."
  def campaign_record(campaign) do
    campaign
    |> campaign()
    |> Map.merge(%{
      hours_per_day: campaign.hours_per_day,
      cents_per_impression: campaign.cents_per_impression,
      paid_cents: campaign.paid_cents,
      starts_on: campaign.starts_on,
      ends_on: campaign.ends_on
    })
  end

  def errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
