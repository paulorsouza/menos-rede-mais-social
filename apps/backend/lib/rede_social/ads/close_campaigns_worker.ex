defmodule RedeSocial.Ads.CloseCampaignsWorker do
  @moduledoc """
  Todo dia, encerra as campanhas que acabaram e devolve por PIX o que não
  foi entregue (Oban.Plugins.Cron, em config/config.exs).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    RedeSocial.Ads.close_ended_campaigns()
    :ok
  end
end
