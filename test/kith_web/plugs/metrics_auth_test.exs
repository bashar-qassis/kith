defmodule KithWeb.Plugs.MetricsAuthTest do
  use KithWeb.ConnCase

  describe "GET /metrics" do
    test "returns 401 without Authorization header", %{conn: conn} do
      conn = get(conn, "/metrics")
      assert conn.status == 401
    end

    test "returns 401 with wrong Bearer token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-token")
        |> get("/metrics")

      assert conn.status == 401
    end

    test "authenticates with correct Bearer token", %{conn: conn} do
      token = Application.get_env(:kith, :metrics_token)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/metrics")

      # PromEx may not be initialized in test, so we get 503 instead of 200.
      # The key assertion is that auth passed (not 401).
      assert conn.status in [200, 503]
    end
  end
end
