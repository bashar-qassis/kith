defmodule Kith.DAV.WellKnownCardDAVPlug do
  @moduledoc """
  Redirects `/.well-known/carddav` to the DAV principal URL for any HTTP method.

  RFC 6764 §5 requires servers to redirect well-known URI requests. Some clients
  (Apple Contacts, Thunderbird) use PROPFIND instead of GET, so this plug handles
  all methods rather than relying on Phoenix's method-specific routing.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> put_resp_header("location", "/dav/principals/")
    |> send_resp(301, "")
  end
end
