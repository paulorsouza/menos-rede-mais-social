defmodule RedeSocialWeb.DemoController do
  @moduledoc """
  Rotas que só existem na demonstração: as pessoas de exemplo e o gov.br
  simulado. Em produção o cadastro vem do gov.br de verdade.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.{Accounts, Ads, Demo}
  alias RedeSocial.Accounts.{CNPJ, CPF}
  alias RedeSocial.Payments.Pix
  alias RedeSocial.Repo
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
      # O banco simulado ganha uma chave PIX desta pessoa, para ela poder
      # cadastrar no painel do criador: <apelido>@pix.demo.
      {:ok, cpf} = CPF.normalize(params["cpf"])
      Pix.Demo.register("#{account.nickname}@pix.demo", cpf, account.nickname)

      conn
      |> Auth.log_in(account)
      |> put_status(:created)
      |> json(%{account: Present.me(account)})
    end
  end

  def test_cnpj(conn, _params) do
    json(conn, %{cnpj: CNPJ.format(CNPJ.generate_for_testing())})
  end

  @doc "Faz o papel do banco: paga a cobrança e avisa a rede, como o aviso (webhook) de um PSP."
  def pay_charge(conn, %{"txid" => txid}) do
    with %{price_cents: cents} <- Repo.get_by(Ads.Campaign, charge_txid: txid),
         {:ok, campaign} <- Ads.confirm_payment(txid, cents) do
      json(conn, %{ok: true, status: campaign.status})
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
