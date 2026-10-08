defmodule RedeSocialWeb.HealthController do
  @moduledoc """
  Diz se o backend está no ar e se consegue falar com o banco.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.Repo

  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} ->
        json(conn, %{status: "ok", database: "ok"})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "degraded", database: "error"})
    end
  end
end
