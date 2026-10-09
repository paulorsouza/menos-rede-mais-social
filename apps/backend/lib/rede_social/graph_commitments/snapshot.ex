defmodule RedeSocial.GraphCommitments.Snapshot do
  @moduledoc "Um retrato do grafo. O sal dos pseudônimos nunca sai do banco."
  use Ecto.Schema

  schema "graph_snapshots" do
    field :root, :binary
    field :salt, :binary, redact: true
    field :size, :integer
    field :registro_position, :integer
    field :taken_at, :utc_datetime
  end
end
