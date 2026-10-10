defmodule RedeSocial.Uploads.PurgeWorker do
  @moduledoc "Apaga, de hora em hora, os envios abandonados há mais de um dia."
  use Oban.Worker, queue: :default, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    RedeSocial.Uploads.purge_stale()
    :ok
  end
end
