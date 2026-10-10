defmodule RedeSocial.Media.TranscodeWorker do
  @moduledoc """
  Converte um vídeo na fila `video`. Em produção, essa fila roda nas
  máquinas que recebem os envios, porque o original fica no disco delas;
  as outras máquinas do backend sobem com a fila desligada.
  """
  use Oban.Worker, queue: :video, max_attempts: 3, unique: [period: :infinity, keys: [:asset_id]]

  alias RedeSocial.Media
  alias RedeSocial.Media.Asset
  alias RedeSocial.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"asset_id" => id}, attempt: attempt, max_attempts: max}) do
    case Repo.get(Asset, id) do
      %Asset{status: :processing} = asset ->
        case Media.process(asset) do
          {:ok, _asset} ->
            :ok

          {:error, :no_source} ->
            Media.fail(asset, :no_source)
            {:cancel, :no_source}

          {:error, reason} when attempt >= max ->
            Media.fail(asset, reason)
            {:error, reason}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:cancel, :not_processing}
    end
  end

  # A conversão de um vídeo longo leva tempo; uma hora é o teto.
  @impl Oban.Worker
  def timeout(_job), do: :timer.hours(1)
end
