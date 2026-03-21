defmodule Kith.DAV.XMLBuilder do
  @moduledoc """
  Builds WebDAV/CardDAV XML responses.

  Uses simple string interpolation rather than a full XML library. This is
  sufficient for the well-defined DAV response vocabulary and avoids adding
  a dependency.
  """

  @doc "Wraps response elements in a DAV multistatus envelope."
  def multistatus(responses) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:cs="http://calendarserver.org/ns/">
    #{Enum.join(responses, "\n")}
    </d:multistatus>
    """
  end

  @doc "Builds a single DAV response element with an href and propstat children."
  def response(href, propstats) do
    """
    <d:response>
    <d:href>#{escape(href)}</d:href>
    #{Enum.join(propstats, "\n")}
    </d:response>
    """
  end

  @doc "Builds a propstat element wrapping properties with an HTTP status."
  def propstat(props, status \\ "HTTP/1.1 200 OK") do
    """
    <d:propstat>
    <d:prop>
    #{Enum.join(props, "\n")}
    </d:prop>
    <d:status>#{status}</d:status>
    </d:propstat>
    """
  end

  # ── Common DAV properties ──────────────────────────────────────────────

  def displayname(name), do: "<d:displayname>#{escape(name)}</d:displayname>"
  def resourcetype(types), do: "<d:resourcetype>#{types}</d:resourcetype>"
  def getcontenttype(type), do: "<d:getcontenttype>#{type}</d:getcontenttype>"
  def getetag(etag), do: "<d:getetag>\"#{escape(etag)}\"</d:getetag>"

  def getlastmodified(dt),
    do: "<d:getlastmodified>#{format_http_date(dt)}</d:getlastmodified>"

  # ── CardDAV-specific properties ────────────────────────────────────────

  def addressbook_description(desc),
    do: "<card:addressbook-description>#{escape(desc)}</card:addressbook-description>"

  def supported_address_data do
    "<card:supported-address-data>" <>
      "<card:address-data-type content-type=\"text/vcard\" version=\"3.0\"/>" <>
      "</card:supported-address-data>"
  end

  def address_data(vcard), do: "<card:address-data>#{escape(vcard)}</card:address-data>"

  # ── CalendarServer extensions (CTag) ───────────────────────────────────

  def getctag(ctag), do: "<cs:getctag>#{escape(ctag)}</cs:getctag>"

  # ── Sync / Discovery ──────────────────────────────────────────────────

  def sync_token(token), do: "<d:sync-token>#{escape(token)}</d:sync-token>"

  def current_user_principal(href),
    do: "<d:current-user-principal><d:href>#{escape(href)}</d:href></d:current-user-principal>"

  # ── XML escaping ──────────────────────────────────────────────────────

  @doc "Escapes XML special characters in text content."
  def escape(nil), do: ""

  def escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  def escape(text), do: escape(to_string(text))

  # ── Helpers ────────────────────────────────────────────────────────────

  defp format_http_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%a, %d %b %Y %H:%M:%S GMT")
  end

  defp format_http_date(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> format_http_date()
  end

  defp format_http_date(_), do: ""
end
