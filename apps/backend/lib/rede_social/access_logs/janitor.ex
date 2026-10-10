defmodule RedeSocial.AccessLogs.Janitor do
  @moduledoc "Uma vez por dia, apaga os registros de acesso que passaram de seis meses."
  use GenServer

  require Logger

  alias RedeSocial.AccessLogs

  @every :timer.hours(24)

  def start_link(_options), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    send(self(), :purge)
    {:ok, nil}
  end

  @impl true
  def handle_info(:purge, state) do
    count = AccessLogs.purge()
    if count > 0, do: Logger.info("registros de acesso vencidos apagados: #{count}")
    Process.send_after(self(), :purge, @every)
    {:noreply, state}
  end
end
