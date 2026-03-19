defmodule KithWeb.Plugs.CSP do
  @moduledoc """
  Plug that sets a Content-Security-Policy header with dynamic `img-src`
  for Immich thumbnails when IMMICH_BASE_URL is configured.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    img_src = build_img_src()

    csp =
      "default-src 'self'; " <>
        "script-src 'self' 'unsafe-inline'; " <>
        "style-src 'self' 'unsafe-inline'; " <>
        "img-src 'self' data: blob: #{img_src}; " <>
        "font-src 'self' data:; " <>
        "connect-src 'self' wss:; " <>
        "frame-src 'none'"

    put_resp_header(conn, "content-security-policy", String.trim(csp))
  end

  defp build_img_src do
    case System.get_env("IMMICH_BASE_URL") do
      nil -> ""
      "" -> ""
      url -> url
    end
  end
end
