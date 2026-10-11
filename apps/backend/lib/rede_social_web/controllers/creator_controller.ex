defmodule RedeSocialWeb.CreatorController do
  @moduledoc "O painel do criador: estimativa do mês, chave PIX e extratos fechados."
  use RedeSocialWeb, :controller

  alias RedeSocial.{Ads, Payments}
  alias RedeSocialWeb.Present

  action_fallback RedeSocialWeb.FallbackController

  def show(conn, _params) do
    with {:ok, dashboard} <- Ads.dashboard(conn.assigns.current_account) do
      json(conn, dashboard)
    end
  end

  def pix(conn, %{"key" => key}) do
    with {:ok, pix_key} <- Payments.register_pix_key(conn.assigns.current_account, key) do
      json(conn, %{pix_key: %{kind: pix_key.kind, hint: pix_key.hint}})
    end
  end

  def pix(_conn, _params), do: {:error, :invalid_pix_key}

  @doc "A empresa da conta, para receber como empresa (chave PIX no CNPJ)."
  def company(conn, params) do
    with {:ok, company} <-
           RedeSocial.Ads.register_advertiser(conn.assigns.current_account, params) do
      json(conn, %{
        company: %{name: company.name, cnpj: RedeSocial.Accounts.CNPJ.format(company.cnpj)}
      })
    end
  end

  @doc "Um extrato fechado, linha a linha, para ler na tela."
  def statement(conn, %{"month" => month}) do
    with %{} = statement <- Payments.statement(conn.assigns.current_account, month) do
      json(conn, %{statement: Present.statement(statement)})
    end
  end

  @doc "O mesmo extrato com as provas, para baixar e conferir no verificador."
  def statement_file(conn, %{"month" => month}) do
    with %{} = statement <- Payments.statement(conn.assigns.current_account, month) do
      conn
      |> put_resp_header("content-disposition", ~s(attachment; filename="extrato-#{month}.json"))
      |> json(Payments.statement_file(statement))
    end
  end
end
