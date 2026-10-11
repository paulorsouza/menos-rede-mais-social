defmodule RedeSocial.Payments.Pix do
  @moduledoc """
  O banco que movimenta o dinheiro da rede pelo PIX: recebe dos anunciantes
  (cobrança com "copia e cola") e paga os criadores (transferência para a
  chave deles). A rede não guarda dado de cartão nem de conta de ninguém.

  Quem operar a rede contrata um banco (um PSP) e escreve o adaptador dele
  com estas funções. A demonstração usa um banco simulado (Pix.Demo).
  """

  @doc "De quem é a chave: o documento (CPF ou CNPJ) e o nome, pelo diretório do PIX (DICT)."
  @callback lookup_key(key :: String.t()) ::
              {:ok, %{document: String.t(), name: String.t()}} | {:error, :not_found}

  @doc "Paga um valor para uma chave. O id evita pagar duas vezes a mesma coisa."
  @callback transfer(key :: String.t(), cents :: pos_integer(), idempotency_id :: String.t()) ::
              {:ok, e2e_id :: String.t()} | {:error, term()}

  @doc """
  Devolve parte de uma cobrança recebida para quem pagou (a devolução do
  PIX). O id evita devolver duas vezes.
  """
  @callback refund(txid :: String.t(), cents :: pos_integer(), idempotency_id :: String.t()) ::
              {:ok, e2e_id :: String.t()} | {:error, term()}

  @doc "Cria uma cobrança e devolve o código copia e cola."
  @callback create_charge(cents :: pos_integer(), txid :: String.t(), description :: String.t()) ::
              {:ok, brcode :: String.t()} | {:error, term()}

  def lookup_key(key), do: adapter().lookup_key(key)
  def transfer(key, cents, id), do: adapter().transfer(key, cents, id)
  def refund(txid, cents, id), do: adapter().refund(txid, cents, id)

  def create_charge(cents, txid, description),
    do: adapter().create_charge(cents, txid, description)

  defp adapter, do: Application.get_env(:rede_social, :pix_adapter, RedeSocial.Payments.Pix.Demo)
end
