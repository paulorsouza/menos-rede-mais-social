defmodule RedeSocial.Ads.Advertiser do
  @moduledoc "Uma empresa que anuncia, pelo CNPJ."
  use Ecto.Schema

  schema "advertisers" do
    belongs_to :account, RedeSocial.Accounts.Account, type: :binary_id
    field :cnpj, :string
    field :name, :string
    timestamps(type: :utc_datetime)
  end
end
