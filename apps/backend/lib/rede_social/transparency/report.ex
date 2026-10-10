defmodule RedeSocial.Transparency.Report do
  @moduledoc "Um relatório trimestral publicado."
  use Ecto.Schema

  schema "transparency_reports" do
    # "2026-T3".
    field :quarter, :string
    field :body, :string
    field :sha256, :string
    field :registro_position, :integer
    field :published_at, :utc_datetime
  end
end
