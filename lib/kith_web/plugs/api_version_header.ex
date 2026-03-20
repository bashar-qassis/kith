defmodule KithWeb.Plugs.ApiVersionHeader do
  @moduledoc """
  Adds `X-Kith-Version: 1` header to all API responses.

  API versioning strategy:
  - v1 uses `/api` prefix (no version in URL)
  - Future breaking changes will use `/api/v2` with a new router scope
  - v1 will remain available during a deprecation period
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    put_resp_header(conn, "x-kith-version", "1")
  end
end
