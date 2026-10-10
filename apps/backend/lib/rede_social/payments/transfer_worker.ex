defmodule RedeSocial.Payments.TransferWorker do
  @moduledoc "Manda o PIX de um extrato. Se o banco falhar, tenta de novo mais tarde."
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:payout_id]]

  alias RedeSocial.{Payments, Repo}
  alias RedeSocial.Payments.Payout

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payout_id" => id}, attempt: attempt, max_attempts: max}) do
    with %Payout{} = payout <- Repo.get(Payout, id),
         {:error, reason} <- Payments.transfer(payout) do
      if attempt >= max, do: Payments.fail(payout, reason)
      {:error, reason}
    else
      nil -> {:cancel, :not_found}
      {:ok, _payout} -> :ok
    end
  end
end
