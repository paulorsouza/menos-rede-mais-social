defmodule RedeSocial.Transparency do
  @moduledoc """
  O que a página de transparência mostra: os parâmetros que o motor está usando
  (com o hash de cada arquivo), os números da rede, a biblioteca de anúncios e
  quanto custa uma hora de vídeo, e os relatórios trimestrais já publicados.
  """

  alias RedeSocial.{Accounts, Ads, Engine, Identification, Moderation, Payments, Social}
  alias RedeSocial.Media.Costs
  alias RedeSocial.Moderation.Rules

  def report do
    engine =
      case Engine.transparency() do
        {:ok, body} -> Map.put(body, "status", "ok")
        {:error, _reason} -> %{"status" => "offline"}
      end

    %{
      engine: engine,
      accounts: Accounts.count_by_kind(),
      posts: Social.count_by_kind(),
      removals: Social.count_removed(),
      moderation: Moderation.public_stats(),
      identifications: Identification.public_log(),
      rules: Rules.all(),
      ads: Ads.library(),
      ad_rules: Ads.Rules.all(),
      open_accounts: Payments.open_accounts(),
      quarterly_reports: RedeSocial.Transparency.Quarterly.list(),
      video: %{params: Costs.params_file(), costs: Costs.summary()}
    }
  end
end
