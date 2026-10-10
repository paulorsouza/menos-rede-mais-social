defmodule RedeSocialWeb.RemovalRequestController do
  @moduledoc """
  Pedidos de remoção vindos de fora, para o setor jurídico. Ver
  RedeSocial.RemovalRequests.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.RemovalRequests
  alias RedeSocial.RemovalRequests.Request

  action_fallback RedeSocialWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{requests: Enum.map(RemovalRequests.list(), &present/1)})
  end

  def create(conn, params) do
    attrs = Map.take(params, ~w(kind authority legal_basis case_number secret_case))

    with {:ok, request} <-
           RemovalRequests.create(conn.assigns.current_account, post_id(params["post"]), attrs) do
      conn
      |> put_status(:created)
      |> json(%{request: present(RemovalRequests.get(request.id))})
    end
  end

  def comply(conn, %{"id" => id} = params) do
    with %Request{} = request <- RemovalRequests.get(id),
         {:ok, request} <-
           RemovalRequests.comply(conn.assigns.current_account, request, params["rule"]) do
      json(conn, %{request: present(request)})
    end
  end

  def refuse(conn, %{"id" => id} = params) do
    with %Request{} = request <- RemovalRequests.get(id),
         {:ok, request} <-
           RemovalRequests.refuse(conn.assigns.current_account, request, params["reason"]) do
      json(conn, %{request: present(request)})
    end
  end

  # Aceita o número do post ou o link dele (…/p/123).
  defp post_id(value) when is_integer(value), do: value

  defp post_id(value) when is_binary(value) do
    case Regex.run(~r/(\d+)\s*$/, value) do
      [_, id] -> String.to_integer(id)
      nil -> nil
    end
  end

  defp post_id(_value), do: nil

  defp present(%Request{} = request) do
    %{
      id: request.id,
      post_id: request.post_id,
      post_body: request.post && request.post.body,
      kind: request.kind,
      authority: request.authority,
      legal_basis: request.legal_basis,
      case_number: request.case_number,
      secret_case: request.secret_case,
      status: request.status,
      rule: request.rule,
      refusal_reason: request.refusal_reason,
      created_at: request.inserted_at,
      decided_at: request.decided_at,
      registro_position: request.registro_position
    }
  end
end
