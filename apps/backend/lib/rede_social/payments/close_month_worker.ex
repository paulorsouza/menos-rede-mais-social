defmodule RedeSocial.Payments.CloseMonthWorker do
  @moduledoc """
  No primeiro dia de cada mês, fecha o mês anterior (Oban.Plugins.Cron, em
  config/config.exs). Mês já fechado não fecha de novo.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias RedeSocial.Payments

  @impl Oban.Worker
  def perform(_job) do
    previous = Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: -1)

    case Payments.close_month(previous) do
      {:ok, _month, _payouts} -> :ok
      {:error, :already_closed} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
