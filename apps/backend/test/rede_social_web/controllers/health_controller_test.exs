defmodule RedeSocialWeb.HealthControllerTest do
  use RedeSocialWeb.ConnCase, async: true

  test "GET /api/health responde que o backend e o banco estão no ar", %{conn: conn} do
    conn = get(conn, ~p"/api/health")

    assert json_response(conn, 200) == %{"status" => "ok", "database" => "ok"}
  end
end
