defmodule KithWeb.DAV.WellKnownTest do
  @moduledoc """
  Tests for CardDAV service discovery via well-known URI.

  RFC 6764 Section 5: Clients use /.well-known/carddav to locate the
  CardDAV service. The server MUST NOT locate the actual service endpoint
  at the well-known URI itself — it MUST redirect.
  """
  use KithWeb.ConnCase, async: true

  import KithWeb.DAV.TestHelpers

  describe "RFC 6764 §5 — well-known CardDAV discovery" do
    test "GET MUST redirect with a 3xx status (uses 301)", %{conn: conn} do
      conn = get(conn, "/.well-known/carddav")
      assert conn.status in 300..399
    end

    test "MUST include Location header pointing to the DAV service", %{conn: conn} do
      conn = get(conn, "/.well-known/carddav")
      [location] = get_resp_header(conn, "location")
      assert location == "/dav/principals/"
    end

    test "MUST NOT serve content at the well-known URI itself", %{conn: conn} do
      conn = get(conn, "/.well-known/carddav")
      assert conn.resp_body == ""
    end

    test "MAY require authentication but need not (this server does not)", %{conn: conn} do
      # RFC 6764 §5: servers MAY require authentication on the well-known URI.
      # This server allows unauthenticated discovery.
      conn = get(conn, "/.well-known/carddav")
      refute conn.status == 401
    end

    test "PROPFIND MUST also redirect (some clients use PROPFIND for discovery)",
         %{conn: conn} do
      conn = dav_request(conn, "PROPFIND", "/.well-known/carddav")
      assert conn.status in 300..399
      [location] = get_resp_header(conn, "location")
      assert location == "/dav/principals/"
    end
  end
end
