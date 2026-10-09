defmodule RedeSocial.Registro.Entry do
  @moduledoc "Uma entrada do registro público."
  use Ecto.Schema

  @primary_key {:position, :integer, autogenerate: false}
  schema "registro_entries" do
    field :kind, :string
    field :data, :string
    field :leaf_hash, :binary
    field :inserted_at, :utc_datetime
  end
end
