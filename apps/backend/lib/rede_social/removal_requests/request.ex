defmodule RedeSocial.RemovalRequests.Request do
  @moduledoc "Um pedido de remoção vindo de fora, registrado pelo setor jurídico."
  use Ecto.Schema
  import Ecto.Changeset

  schema "removal_requests" do
    belongs_to :post, RedeSocial.Social.Post
    belongs_to :requested_by, RedeSocial.Accounts.Account, type: :binary_id
    field :kind, :string
    field :authority, :string
    field :legal_basis, :string
    field :case_number, :string
    field :secret_case, :boolean, default: false
    field :status, :string, default: "recebido"
    # A regra citada na remoção: 9 (ordem judicial) ou a regra pública que o
    # post quebrou, quando o pedido não é judicial.
    field :rule, :integer
    field :refusal_reason, :string
    belongs_to :decided_by, RedeSocial.Accounts.Account, type: :binary_id
    field :decided_at, :utc_datetime
    field :registro_position, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:kind, :authority, :legal_basis, :case_number, :secret_case])
    |> update_change(:authority, &String.trim/1)
    |> update_change(:legal_basis, &String.trim/1)
    |> update_change(:case_number, &String.trim/1)
    |> validate_required([:kind], message: "diga se o pedido é judicial")
    |> validate_inclusion(:kind, ["judicial", "outro"], message: "judicial ou outro")
    |> validate_required([:authority], message: "diga quem pediu")
    |> validate_required([:legal_basis], message: "diga a base legal")
    |> validate_length(:authority, max: 200)
    |> validate_length(:legal_basis, max: 200)
    |> validate_length(:case_number, max: 60)
  end
end
