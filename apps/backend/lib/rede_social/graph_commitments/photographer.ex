defmodule RedeSocial.GraphCommitments.Photographer do
  @moduledoc """
  Tira o retrato do grafo no intervalo configurado (`:graph_snapshot_minutes`):
  uma vez por dia em produção, mais vezes na demonstração.
  """
  use GenServer

  require Logger

  alias RedeSocial.GraphCommitments

  def start_link(_options), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Process.send_after(self(), :snapshot, :timer.seconds(5))
    {:ok, nil}
  end

  @impl true
  def handle_info(:snapshot, state) do
    minutes = Application.get_env(:rede_social, :graph_snapshot_minutes, 1_440)
    latest = GraphCommitments.latest()
    due? = latest == nil or DateTime.diff(DateTime.utc_now(), latest.taken_at, :minute) >= minutes

    if due? do
      {:ok, snapshot} = GraphCommitments.take_snapshot()
      Logger.info("retrato do grafo #{snapshot.id}: #{snapshot.size} ligações")
    end

    Process.send_after(self(), :snapshot, :timer.minutes(1))
    {:noreply, state}
  end
end
