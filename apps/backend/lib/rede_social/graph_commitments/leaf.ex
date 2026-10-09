defmodule RedeSocial.GraphCommitments.Leaf do
  @moduledoc "Uma folha de um retrato do grafo: só o hash, na sua posição."
  use Ecto.Schema

  @primary_key false
  schema "graph_snapshot_leaves" do
    field :snapshot_id, :id
    field :position, :integer
    field :leaf_hash, :binary
  end
end
