defmodule RedeSocial.Privacy do
  @moduledoc """
  Os direitos da regra pétrea 11: baixar tudo o que a rede guarda sobre você
  e apagar a conta quando quiser.

  Ao apagar, saem a conta, os posts com as fotos e vídeos, as curtidas, os
  salvamentos, quem você segue e quem te segue, as views, as denúncias, os
  recursos, os avisos, os envios em andamento, as lives, a chave PIX e os
  anúncios que a rede mostrou. A impressão digital do CPF sai junto, então a mesma
  pessoa pode criar outra conta depois. Ficam só registros que não são da
  pessoa e sim da rede, sem o vínculo com ela: as decisões da moderação (que
  alimentam os números públicos) e as impressões de anúncio (que fecham as
  contas dos anunciantes).
  """

  import Ecto.Query

  alias RedeSocial.Accounts.Account
  alias RedeSocial.Ads.{AdSlot, AdView, Advertiser, Campaign, Impression}
  alias RedeSocial.Lives.Live
  alias RedeSocial.Moderation.{Appeal, Notice, Report}
  alias RedeSocial.Payments.{Month, Payout, PixKey}
  alias RedeSocial.{AccessLogs, Repo, Uploads}
  alias RedeSocial.Social.{Follow, Like, MonthlyViews, Post, Save, View}
  alias RedeSocial.Uploads.Upload

  @doc "Tudo o que a rede guarda sobre a conta, num mapa pronto para virar JSON."
  def export(%Account{id: id} = account) do
    %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      about:
        "Tudo o que a -rede+social guarda sobre esta conta. O CPF não está aqui porque a rede não " <>
          "guarda o número: só uma impressão digital, que não dá para reverter.",
      account: %{
        nickname: account.nickname,
        bio: account.bio,
        region: account.region,
        govbr_level: account.govbr_level,
        age_band: account.age_band,
        created_at: account.inserted_at
      },
      posts:
        all(
          from p in Post,
            where: p.author_id == ^id,
            order_by: [asc: p.inserted_at],
            select: %{
              id: p.id,
              kind: p.kind,
              body: p.body,
              media_url: p.media_path,
              monetized: p.monetized,
              ad_markers: p.ad_markers,
              created_at: p.inserted_at,
              removed_at: p.removed_at,
              removal_rule: p.removal_rule
            }
        )
        # Endereço assinado: abre nas próximas horas, para baixar os arquivos.
        |> Enum.map(&Map.update!(&1, :media_url, fn path -> RedeSocial.Storage.url(path) end)),
      likes:
        all(
          from l in Like,
            where: l.account_id == ^id,
            select: %{post_id: l.post_id, at: l.inserted_at}
        ),
      saves:
        all(
          from s in Save,
            where: s.account_id == ^id,
            select: %{post_id: s.post_id, at: s.inserted_at}
        ),
      following:
        all(
          from f in Follow,
            join: a in Account,
            on: a.id == f.followed_id,
            where: f.follower_id == ^id,
            select: %{nickname: a.nickname, since: f.inserted_at}
        ),
      followers:
        all(
          from f in Follow,
            join: a in Account,
            on: a.id == f.follower_id,
            where: f.followed_id == ^id,
            select: %{nickname: a.nickname, since: f.inserted_at}
        ),
      views:
        all(
          from v in View,
            where: v.viewer_id == ^id,
            select: %{post_id: v.post_id, watched_ms: v.watched_ms, at: v.inserted_at}
        ),
      monthly_views:
        all(
          from m in MonthlyViews,
            where: m.account_id == ^id,
            select: %{month: m.month, views: m.views}
        ),
      reports:
        all(
          from r in Report,
            where: r.reporter_id == ^id,
            select: %{
              post_id: r.post_id,
              rule: r.rule,
              at: r.inserted_at,
              resolution: r.resolution
            }
        ),
      appeals:
        all(
          from a in Appeal,
            where: a.author_id == ^id,
            select: %{post_id: a.post_id, text: a.text, at: a.inserted_at, outcome: a.outcome}
        ),
      notices:
        all(
          from n in Notice,
            where: n.account_id == ^id,
            select: %{kind: n.kind, rule: n.rule, post_id: n.post_id, at: n.inserted_at}
        ),
      uploads:
        all(
          from u in Upload,
            where: u.account_id == ^id,
            select: %{
              filename: u.filename,
              content_type: u.content_type,
              bytes: u.length,
              started_at: u.inserted_at,
              completed_at: u.completed_at,
              used_at: u.used_at
            }
        ),
      lives:
        all(
          from l in Live,
            where: l.account_id == ^id,
            select: %{
              post_id: l.post_id,
              status: l.status,
              started_at: l.started_at,
              ended_at: l.ended_at
            }
        ),
      ads_seen: ads_seen(id),
      creator: creator(id),
      advertiser: advertiser(id),
      accesses: %{
        about:
          "Datas dos seus acessos, guardadas por seis meses como manda o Marco Civil. O IP de cada " <>
            "acesso fica selado com a chave dos guardiões e só abre com ordem judicial.",
        at: id |> AccessLogs.for_account() |> Enum.map(& &1.inserted_at)
      }
    }
  end

  # Os anúncios que a rede mostrou à pessoa e os que contaram.
  defp ads_seen(id) do
    %{
      shown:
        all(
          from s in AdSlot,
            where: s.viewer_id == ^id,
            select: %{
              campaign_id: s.campaign_id,
              kind: s.kind,
              post_ids: s.post_ids,
              at: s.served_at
            }
        ),
      in_videos:
        all(
          from v in AdView,
            where: v.viewer_id == ^id,
            select: %{
              campaign_id: v.campaign_id,
              post_id: v.post_id,
              moment: v.moment,
              at: v.inserted_at
            }
        ),
      in_shorts:
        all(
          from i in Impression,
            where: i.viewer_id == ^id,
            select: %{campaign_id: i.campaign_id, watched: i.breakdown, at: i.inserted_at}
        )
    }
  end

  # Para quem recebe por anúncio: a chave PIX e cada extrato.
  defp creator(id) do
    key = Repo.get(PixKey, id)

    %{
      pix_key: key && %{kind: key.kind, key: key.key, verified_at: key.verified_at},
      statements:
        all(
          from p in Payout,
            join: m in Month,
            on: m.id == p.month_id,
            where: p.account_id == ^id,
            order_by: [asc: m.month],
            select: %{
              month: m.month,
              total_cents: p.total_cents,
              status: p.status,
              paid_at: p.paid_at,
              pix_e2e_id: p.pix_e2e_id,
              statement: p.result
            }
        )
    }
  end

  # Para quem anuncia: a empresa e as campanhas.
  defp advertiser(id) do
    case Repo.get_by(Advertiser, account_id: id) do
      nil ->
        nil

      advertiser ->
        %{
          cnpj: advertiser.cnpj,
          name: advertiser.name,
          campaigns:
            all(
              from c in Campaign,
                where: c.advertiser_id == ^advertiser.id,
                order_by: [asc: c.id],
                select: %{
                  id: c.id,
                  title: c.title,
                  body: c.body,
                  scope: c.scope,
                  region: c.region,
                  starts_on: c.starts_on,
                  ends_on: c.ends_on,
                  price_cents: c.price_cents,
                  paid_cents: c.paid_cents,
                  status: c.status,
                  rejection_rule: c.rejection_rule
                }
            )
        }
    end
  end

  @doc """
  Apaga a conta. Pede o apelido de volta como confirmação, porque não tem
  como desfazer.
  """
  def delete_account(%Account{nickname: nickname} = account, confirmation) do
    if is_binary(confirmation) and String.downcase(String.trim(confirmation)) == nickname do
      media =
        all(
          from p in Post,
            where:
              p.author_id == ^account.id and
                (not is_nil(p.media_path) or not is_nil(p.media_asset_id)),
            select: %{media_path: p.media_path, media_asset_id: p.media_asset_id}
        )

      uploads = all(from u in Upload, where: u.account_id == ^account.id)

      {:ok, _account} = Repo.delete(account)
      Enum.each(media, &RedeSocial.Media.delete/1)
      # Os envios em andamento saem junto com a linha; os bytes também.
      Enum.each(uploads, &File.rm(Uploads.path(&1)))
      :ok
    else
      {:error, :confirmation}
    end
  end

  defp all(query), do: Repo.all(query)
end
