defmodule RedeSocial.Ads.SlotPurgeWorker do
  @moduledoc "Apaga, uma vez por dia, as exibições de anúncio que já não podem ser contadas."
  use Oban.Worker, queue: :default, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    RedeSocial.Ads.purge_slots()
    :ok
  end
end
