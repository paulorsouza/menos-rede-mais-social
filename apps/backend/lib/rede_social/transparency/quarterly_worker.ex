defmodule RedeSocial.Transparency.QuarterlyWorker do
  @moduledoc """
  No primeiro dia de cada trimestre, publica o relatório do anterior
  (Oban.Plugins.Cron, em config/config.exs).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias RedeSocial.Transparency.Quarterly

  @impl Oban.Worker
  def perform(_job) do
    previous = Date.utc_today() |> Date.shift(month: -3)

    case Quarterly.publish(previous) do
      {:ok, _report} -> :ok
      {:error, :already_published} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
