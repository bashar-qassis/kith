defmodule KithWeb.WellKnownController do
  @moduledoc """
  Handles well-known URI redirects for protocol auto-discovery.

  CardDAV clients (Apple Contacts, DAVx5, Thunderbird) query
  `/.well-known/carddav` to discover the DAV service root.

  See RFC 6764 Section 5.
  """

  use KithWeb, :controller

  @doc """
  Redirects CardDAV discovery requests to the DAV principal URL.
  """
  def carddav(conn, _params) do
    conn
    |> put_resp_header("location", "/dav/principals/")
    |> send_resp(301, "")
  end
end
