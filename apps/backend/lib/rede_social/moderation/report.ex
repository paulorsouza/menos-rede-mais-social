defmodule RedeSocial.Moderation.Report do
  @moduledoc "Uma denúncia: alguém diz que um post quebra uma regra."
  use Ecto.Schema

  schema "reports" do
    belongs_to :post, RedeSocial.Social.Post
    belongs_to :reporter, RedeSocial.Accounts.Account, type: :binary_id
    field :rule, :integer

    # "removed" quando o post saiu, "kept" quando a moderação manteve.
    field :resolution, :string
    field :resolved_at, :utc_datetime
    belongs_to :resolved_by, RedeSocial.Accounts.Account, type: :binary_id

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
