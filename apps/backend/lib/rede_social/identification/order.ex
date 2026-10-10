defmodule RedeSocial.Identification.Order do
  @moduledoc "Uma ordem judicial para identificar quem está por trás de uma conta."
  use Ecto.Schema
  import Ecto.Changeset

  schema "identification_orders" do
    field :account_id, :binary_id
    field :court, :string
    field :case_number, :string
    field :secret_case, :boolean, default: false

    # "collecting" enquanto os guardiões mandam as partes; "opened" depois.
    field :status, :string, default: "collecting"
    field :opened_at, :utc_datetime
    belongs_to :requested_by, RedeSocial.Accounts.Account, type: :binary_id
    belongs_to :opened_by, RedeSocial.Accounts.Account, type: :binary_id
    has_many :partials, RedeSocial.Identification.OrderPartial

    timestamps(type: :utc_datetime)
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:court, :case_number, :secret_case])
    |> update_change(:court, &String.trim/1)
    |> update_change(:case_number, &String.trim/1)
    |> validate_required([:court], message: "diga qual juízo mandou")
    |> validate_length(:court, max: 200)
    |> validate_length(:case_number, max: 60)
  end
end
