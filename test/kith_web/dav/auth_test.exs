defmodule KithWeb.DAV.AuthTest do
  @moduledoc "RFC 7617 — HTTP Basic Authentication for CardDAV."
  use KithWeb.ConnCase, async: true

  import KithWeb.DAV.TestHelpers

  setup :setup_dav_user

  describe "RFC 7617 §2 — Basic authentication scheme" do
    test "MUST return 401 when no Authorization header is present", %{conn: conn} do
      conn = dav_request(conn, "PROPFIND", "/dav/")
      assert conn.status == 401
    end

    test "401 response MUST include WWW-Authenticate header with Basic scheme and realm",
         %{conn: conn} do
      conn = dav_request(conn, "PROPFIND", "/dav/")
      [www_auth] = get_resp_header(conn, "www-authenticate")
      assert www_auth =~ ~r/Basic\s+realm=/i
    end

    test "MUST reject invalid credentials (wrong password)", %{conn: conn, user: user} do
      conn =
        conn
        |> basic_auth(user.email, "wrong-password")
        |> dav_request("PROPFIND", "/dav/")

      assert conn.status == 401
    end

    test "MUST reject malformed base64 in Authorization header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic !!!invalid-base64!!!")
        |> dav_request("PROPFIND", "/dav/")

      assert conn.status == 401
    end

    test "MUST reject non-Basic authentication scheme", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer some-token")
        |> dav_request("PROPFIND", "/dav/")

      assert conn.status == 401
    end

    test "MUST accept valid base64(userid:password) credentials", context do
      conn = authed_dav(context, "PROPFIND", "/dav/")
      refute conn.status == 401
    end
  end
end
