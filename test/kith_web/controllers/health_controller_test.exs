defmodule KithWeb.HealthControllerTest do
  use KithWeb.ConnCase

  describe "GET /health/live" do
    test "returns 200 with ok status", %{conn: conn} do
      conn = get(conn, "/health/live")
      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "does not require authentication", %{conn: conn} do
      conn = get(conn, "/health/live")
      assert conn.status == 200
    end

    test "returns application/json content type", %{conn: conn} do
      conn = get(conn, "/health/live")
      assert {"content-type", content_type} = List.keyfind(conn.resp_headers, "content-type", 0)
      assert content_type =~ "application/json"
    end
  end

  describe "GET /health/ready" do
    test "returns 200 when database is connected and migrations current", %{conn: conn} do
      conn = get(conn, "/health/ready")
      body = json_response(conn, 200)
      assert body["status"] == "ok"
      assert body["db"] == "connected"
      assert body["migrations"] == "current"
    end

    test "does not require authentication", %{conn: conn} do
      conn = get(conn, "/health/ready")
      assert conn.status == 200
    end
  end

  describe "GET /health (backward compatible)" do
    test "returns 200 with ok status", %{conn: conn} do
      conn = get(conn, "/health")
      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end
end
