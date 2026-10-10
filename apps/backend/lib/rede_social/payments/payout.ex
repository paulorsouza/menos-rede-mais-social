defmodule RedeSocial.Payments.Payout do
  @moduledoc """
  O extrato de um criador num mês, guardado do jeito que foi fechado (a
  entrada e o resultado do motor), e o repasse por PIX.
  """
  use Ecto.Schema

  schema "payouts" do
    belongs_to :month, RedeSocial.Payments.Month
    belongs_to :account, RedeSocial.Accounts.Account, type: :binary_id
    field :input, :map
    field :result, :map
    field :total_cents, :integer
    field :payable, :boolean
    # sending: na fila do PIX; paid: chegou; carried: abaixo do mínimo, fica
    # para o mês seguinte; no_key: falta a chave PIX; failed: o banco recusou.
    field :status, Ecto.Enum, values: [:sending, :paid, :carried, :no_key, :failed]
    field :pix_key_hint, :string
    field :pix_e2e_id, :string
    field :paid_at, :utc_datetime
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
