defmodule RedeSocial.Lives.Watcher do
  @moduledoc """
  De tempos em tempos, pergunta ao servidor de transmissão quais lives
  estão mandando imagem. Live que sumiu em duas conferidas seguidas acabou
  (a pessoa encerrou, fechou o OBS ou a conexão caiu de vez). Também desfaz
  lives abertas que nunca começaram.
  """
  use GenServer

  require Logger

  alias RedeSocial.Lives
  alias RedeSocial.Lives.Live

  @interval :timer.seconds(5)
  @misses_to_end 2

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_state) do
    schedule()
    {:ok, %{misses: %{}, online: true}}
  end

  @impl true
  def handle_info(:check, state) do
    schedule()

    case ready_paths() do
      {:ok, ready} ->
        Lives.expire_waiting()
        {:noreply, %{state | misses: check(Lives.list_live(), ready, state.misses), online: true}}

      # Avisa uma vez quando o servidor some, e não a cada conferida.
      {:error, reason} ->
        if state.online,
          do: Logger.warning("servidor de transmissão fora do ar: #{inspect(reason)}")

        {:noreply, %{state | online: false}}
    end
  end

  defp check(lives, ready, misses) do
    Enum.reduce(lives, %{}, fn live, acc ->
      if MapSet.member?(ready, Live.path(live)) do
        acc
      else
        count = Map.get(misses, live.id, 0) + 1

        if count >= @misses_to_end do
          Lives.finish(live)
          acc
        else
          Map.put(acc, live.id, count)
        end
      end
    end)
  end

  @doc "Os caminhos que estão recebendo imagem agora, pela API do MediaMTX."
  def ready_paths do
    url = Application.get_env(:rede_social, :ao_vivo, [])[:api] <> "/v3/paths/list"

    case Req.get(url, retry: false, receive_timeout: 3000) do
      {:ok, %{status: 200, body: %{"items" => items}}} ->
        {:ok, for(%{"name" => name, "ready" => true} <- items, into: MapSet.new(), do: name)}

      {:ok, response} ->
        {:error, response.status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule, do: Process.send_after(self(), :check, @interval)
end
