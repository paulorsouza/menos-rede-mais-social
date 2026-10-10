defmodule RedeSocial.Privacy do
  @moduledoc """
  Os direitos da regra pétrea 11: baixar tudo o que a rede guarda sobre você
  e apagar a conta quando quiser.

  Ao apagar, saem a conta, os posts com as fotos e vídeos, as curtidas, os
  salvamentos, quem você segue e quem te segue, as views, as denúncias, os
  recursos e os avisos. A impressão digital do CPF sai junto, então a mesma
  pessoa pode criar outra conta depois. Ficam só registros que não são da
  pessoa e sim da rede, sem o vínculo com ela: as decisões da moderação (que
  alimentam os números públicos) e as impressões de anúncio (que fecham as
  contas dos anunciantes).
  """

  import Ecto.Query

  alias RedeSocial.Accounts.Account
  alias RedeSocial.Moderation.{Appeal, Notice, Report}
  alias RedeSocial.{AccessLogs, Repo}
  alias RedeSocial.Social.{Follow, Like, MonthlyViews, Post, Save, View}

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
        ),
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
      accesses: %{
        about:
          "Datas dos seus acessos, guardadas por seis meses como manda o Marco Civil. O IP de cada " <>
            "acesso fica selado com a chave dos guardiões e só abre com ordem judicial.",
        at: id |> AccessLogs.for_account() |> Enum.map(& &1.inserted_at)
      }
    }
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

      {:ok, _account} = Repo.delete(account)
      Enum.each(media, &RedeSocial.Media.delete/1)
      :ok
    else
      {:error, :confirmation}
    end
  end

  defp all(query), do: Repo.all(query)
end
