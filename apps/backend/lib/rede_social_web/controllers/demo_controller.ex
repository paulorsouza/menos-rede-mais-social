defmodule RedeSocialWeb.DemoController do
  @moduledoc """
  Rotas que só existem na demonstração: as pessoas de exemplo e o gov.br
  simulado. Em produção o cadastro vem do gov.br de verdade.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.{Accounts, Demo}
  alias RedeSocial.Accounts.CPF
  alias RedeSocialWeb.{Auth, Present}

  action_fallback RedeSocialWeb.FallbackController

  def personas(conn, _params) do
    personas = Demo.personas() |> Accounts.list_by_nicknames() |> Enum.map(&Present.me/1)
    json(conn, %{personas: personas})
  end

  def test_cpf(conn, _params) do
    json(conn, %{cpf: CPF.format(CPF.generate_for_testing())})
  end

  def register(conn, params) do
    attrs = Map.take(params, ~w(nickname govbr_level age_band region bio))

    with {:ok, account} <- Accounts.register_verified(attrs, params["cpf"]) do
      conn
      |> Auth.log_in(account)
      |> put_status(:created)
      |> json(%{account: Present.me(account)})
    end
  end

  def register_basic(conn, params) do
    with {:ok, account} <- Accounts.register_basic(Map.take(params, ~w(nickname region bio))) do
      conn
      |> Auth.log_in(account)
      |> put_status(:created)
      |> json(%{account: Present.me(account)})
    end
  end
end
