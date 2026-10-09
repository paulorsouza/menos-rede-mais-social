defmodule RedeSocial.Moderation.Appeal do
  @moduledoc "O recurso do autor contra uma remoção."
  use Ecto.Schema
  import Ecto.Changeset

  schema "appeals" do
    belongs_to :post, RedeSocial.Social.Post
    belongs_to :author, RedeSocial.Accounts.Account, type: :binary_id
    field :text, :string

    # "restore" quando o post volta, "uphold" quando a remoção fica.
    field :outcome, :string
    field :decided_at, :utc_datetime
    belongs_to :decided_by, RedeSocial.Accounts.Account, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(appeal, attrs) do
    appeal
    |> cast(attrs, [:text])
    |> update_change(:text, &String.trim/1)
    |> validate_length(:text, max: 1000, message: "no máximo 1000 caracteres")
  end
end
