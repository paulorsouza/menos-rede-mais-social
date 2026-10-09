defmodule RedeSocialWeb.IdentificationController do
  @moduledoc """
  Ordens judiciais de identificação, para o setor jurídico da entidade
  gestora. Ver RedeSocial.Identification.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.{Accounts, Demo, Identification}

  action_fallback RedeSocialWeb.FallbackController

  def index(conn, _params) do
    orders = Identification.list_orders()
    json(conn, %{orders: Enum.map(orders, &order/1), demo: Demo.enabled?()})
  end

  def create(conn, params) do
    attrs = Map.take(params, ~w(court case_number secret_case))

    with {:ok, order} <-
           Identification.create_order(conn.assigns.current_account, params["nickname"], attrs) do
      conn |> put_status(:created) |> json(%{order: order(Identification.get_order(order.id))})
    end
  end

  @doc "O pedido para os guardiões, no formato da linha de comando `cofre`."
  def package(conn, %{"id" => id}) do
    with %{} = order <- find(id) do
      conn
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="pedido-#{order.id}.json")
      )
      |> json(Identification.package(order))
    end
  end

  @doc "As partes de um guardião, como sai do `cofre parcial`."
  def submit(conn, %{"id" => id, "index" => guardian, "partials" => partials}) do
    with %{} = order <- find(id),
         {:ok, order} <- Identification.submit(order, guardian, partials) do
      json(conn, %{order: order(order)})
    end
  end

  def simulate(conn, %{"id" => id, "guardian" => guardian}) do
    with %{} = order <- find(id),
         {guardian, ""} <- Integer.parse(guardian),
         {:ok, order} <- Identification.simulate_guardian(order, guardian) do
      json(conn, %{order: order(order)})
    else
      :error -> {:error, :invalid_guardian}
      other -> other
    end
  end

  @doc "Abre a ordem. O CPF e os IPs aparecem só nesta resposta."
  def open(conn, %{"id" => id}) do
    with %{} = order <- find(id),
         {:ok, result} <- Identification.open(conn.assigns.current_account, order) do
      json(conn, %{result: result, order: order(Identification.get_order(order.id))})
    end
  end

  defp find(id) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> Identification.get_order(id)
      _ -> nil
    end
  end

  defp order(order) do
    account = Accounts.get_account(order.account_id)

    %{
      id: order.id,
      nickname: account && account.nickname,
      court: order.court,
      case_number: order.case_number,
      secret_case: order.secret_case,
      status: order.status,
      created_at: order.inserted_at,
      opened_at: order.opened_at,
      ready_guardians: Identification.ready_guardians(order),
      items: length(Identification.items(order))
    }
  end
end
