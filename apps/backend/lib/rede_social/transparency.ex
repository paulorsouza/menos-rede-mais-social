defmodule RedeSocial.Transparency do
  @moduledoc """
  O que a página de transparência mostra: os parâmetros que o motor está usando
  (com o hash de cada arquivo), os números da rede e a biblioteca de anúncios.
  """

  alias RedeSocial.{Accounts, Ads, Engine, Identification, Moderation, Social}
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
      ads: Ads.library()
    }
  end
end
