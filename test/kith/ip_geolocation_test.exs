defmodule Kith.IpGeolocationTest do
  use Kith.DataCase, async: true

  alias Kith.IpGeolocation

  describe "configured?/0" do
    test "returns false when GEOIP_DB_PATH is not set" do
      refute IpGeolocation.configured?()
    end
  end

  describe "lookup/1 when not configured" do
    test "returns geoip_not_configured error" do
      assert {:error, :geoip_not_configured} = IpGeolocation.lookup("8.8.8.8")
    end
  end

  describe "from_cloudflare_header/1" do
    test "extracts country from CF-IPCountry header" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_req_header("cf-ipcountry", "US")

      assert {:ok, %{country: "US"}} = IpGeolocation.from_cloudflare_header(conn)
    end

    test "returns not_available when header is missing" do
      conn = Plug.Test.conn(:get, "/")
      assert {:error, :not_available} = IpGeolocation.from_cloudflare_header(conn)
    end

    test "rejects XX and T1 country codes" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_req_header("cf-ipcountry", "XX")

      assert {:error, :not_available} = IpGeolocation.from_cloudflare_header(conn)
    end
  end
end
