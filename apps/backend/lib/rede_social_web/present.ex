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
      can_go_live: Accounts.verified?(account) and not Accounts.minor?(account),
      moderator: account.moderator,
      legal_officer: account.legal_officer,
      unread_notices: Moderation.unread_count(account),
      # Na demonstração, botões que fazem o papel do banco e do gov.br.
      demo: RedeSocial.Demo.enabled?()
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
      media_url: RedeSocial.Storage.url(post.media_path),
      media_status: post.media_status,
      poster_url: RedeSocial.Storage.url(post.poster_path),
      captions_url: RedeSocial.Storage.url(post.captions_path),
      duration_ms: post.duration_ms,
      width: post.width,
      height: post.height,
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
    advertiser = campaign.advertiser_record

    campaign
    |> campaign()
    |> Map.merge(%{
      cnpj: advertiser && RedeSocial.Accounts.CNPJ.format(advertiser.cnpj),
      hours_per_day: campaign.hours_per_day,
      cents_per_impression: campaign.cents_per_impression,
      paid_cents: campaign.paid_cents,
      delivered: campaign.delivered,
      starts_on: campaign.starts_on,
      ends_on: campaign.ends_on
    })
  end

  def advertiser(advertiser) do
    %{
      id: advertiser.id,
      name: advertiser.name,
      cnpj: RedeSocial.Accounts.CNPJ.format(advertiser.cnpj)
    }
  end

  @doc "Uma campanha para quem anunciou e para a moderação: situação, preço e cobrança."
  def own_campaign(campaign) do
    campaign
    |> campaign()
    |> Map.merge(%{
      status: campaign.status,
      hours_per_day: campaign.hours_per_day,
      impressions_per_day: campaign.impressions_per_day,
      cents_per_impression: campaign.cents_per_impression,
      price_cents: campaign.price_cents,
      paid_cents: campaign.paid_cents,
      starts_on: campaign.starts_on,
      ends_on: campaign.ends_on,
      rejection_rule:
        campaign.rejection_rule && RedeSocial.Ads.Rules.get(campaign.rejection_rule),
      brcode: if(campaign.status == :awaiting_payment, do: campaign.brcode),
      charge_txid: if(campaign.status == :awaiting_payment, do: campaign.charge_txid)
    })
  end

  @doc "Um extrato fechado, para ler na tela."
  def statement(%{payout: payout, month: month}) do
    input = payout.input
    result = payout.result

    views =
      input["video_views"]
      |> Enum.zip(result["statuses"])
      |> Enum.map(fn {view, status} ->
        %{post_id: view["post"], regional: view["regional"], at: view["at"], status: status}
      end)

    %{
      month: Calendar.strftime(month.month, "%Y-%m"),
      national_views: result["national_views"],
      regional_views: result["regional_views"],
      discarded_views: result["discarded_views"],
      discarded_by_reason:
        views |> Enum.reject(&(&1.status == "counted")) |> Enum.frequencies_by(& &1.status),
      by_post:
        views
        |> Enum.filter(&(&1.status == "counted"))
        |> Enum.frequencies_by(& &1.post_id)
        |> Enum.map(fn {post_id, count} -> %{post_id: post_id, views: count} end)
        |> Enum.sort_by(& &1.views, :desc),
      weighted_views: result["weighted_views"],
      effective_views: result["effective_views"],
      video_cents: result["video_cents"],
      shorts:
        Enum.zip_with(input["shorts"], result["shorts_cents_each"], fn impression, cents ->
          %{
            id: impression["id"],
            at: impression["at"],
            revenue_cents: impression["revenue_cents"],
            my_cents: cents
          }
        end),
      shorts_cents: result["shorts_cents"],
      carry_in_cents: result["carry_in_cents"],
      total_cents: result["total_cents"],
      payable: result["payable"],
      status: payout.status,
      pix_key_hint: payout.pix_key_hint,
      pix_e2e_id: payout.pix_e2e_id,
      paid_at: payout.paid_at,
      root: Base.encode16(month.root, case: :lower),
      registro_position: month.registro_position,
      lines: length(result["leaves"])
    }
  end

  def errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
