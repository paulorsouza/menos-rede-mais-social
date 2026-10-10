defmodule RedeSocial.Social.MonthlyViews do
  @moduledoc "Total de views de um criador num mês. É a base do pagamento por faixas."
  use Ecto.Schema

  @primary_key false
  schema "monthly_views" do
    belongs_to :account, RedeSocial.Accounts.Account, type: :binary_id
    field :month, :date
    field :views, :integer, default: 0
  end
end
