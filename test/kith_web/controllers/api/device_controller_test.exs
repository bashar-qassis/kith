defmodule KithWeb.API.DeviceControllerTest do
  use KithWeb.ConnCase

  import Kith.AccountsFixtures

  defp authed_conn(conn, user) do
    {raw_token, _} = Kith.Accounts.generate_api_token(user)
    put_req_header(conn, "authorization", "Bearer #{raw_token}")
  end

  setup %{conn: conn} do
    user = user_fixture()
    conn = authed_conn(conn, user)
    %{conn: conn, user: user}
  end

  describe "POST /api/devices" do
    test "returns 501 Not Implemented with RFC 7807 body", %{conn: conn} do
      conn = post(conn, ~p"/api/devices", %{"token" => "abc123", "platform" => "ios"})

      body = json_response(conn, 501)
      assert body["title"] == "Not Implemented"
      assert body["status"] == 501
      assert is_binary(body["detail"])
    end

    test "response content-type includes problem+json", %{conn: conn} do
      conn = post(conn, ~p"/api/devices", %{"token" => "abc123"})

      content_type = Plug.Conn.get_resp_header(conn, "content-type") |> List.first()
      assert content_type =~ "problem+json"
    end
  end
end
