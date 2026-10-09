defmodule RedeSocial.Registro.Watcher do
  @moduledoc """
  De tempos em tempos, pergunta ao motor qual versão está rodando, com quais
  parâmetros e com qual chave assina os recibos. Quando algo muda, anota no
  registro público. Assim qualquer pessoa sabe, depois, qual motor e quais
  pesos valiam em cada momento.
  """
  use GenServer

  require Logger

  alias RedeSocial.{Engine, Registro}

  @every :timer.minutes(10)

  def start_link(_options), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    send(self(), :check)
    {:ok, nil}
  end

  @impl true
  def handle_info(:check, state) do
    check()
    Process.send_after(self(), :check, @every)
    {:noreply, state}
  end

  @doc "Anota a versão do motor se ela mudou desde a última entrada."
  def check do
    with {:ok, engine} <- Engine.transparency() do
      case Registro.append_if_changed("motor", payload(engine)) do
        {:ok, :same} ->
          :same

        {:ok, entry} ->
          Logger.info("registro: nova versão do motor na posição #{entry.position}")
          :appended
      end
    else
      {:error, reason} ->
        Logger.warning("registro: motor fora do ar (#{inspect(reason)})")
        :offline
    end
  end

  defp payload(engine) do
    %{
      versao: engine["engine_version"],
      build: engine["engine_build"],
      feed_sha256: get_in(engine, ["feed_params", "sha256"]),
      anuncios_sha256: get_in(engine, ["ads_params", "sha256"]),
      guardioes_sha256: get_in(engine, ["guardians_params", "sha256"]),
      chave_recibos: engine["receipt_public_key"]
    }
  end
end
