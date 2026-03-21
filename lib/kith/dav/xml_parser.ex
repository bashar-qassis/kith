defmodule Kith.DAV.XMLParser do
  @moduledoc """
  Parses WebDAV/CardDAV XML request bodies.

  Uses simple regex-based parsing rather than a full XML parser. DAV request
  bodies are well-structured and limited in vocabulary, so this approach is
  sufficient and avoids adding a dependency.
  """

  @doc """
  Parses a PROPFIND request body.

  Returns `{:ok, :allprop}`, `{:ok, :propname}`, or `{:ok, {:prop, props}}`
  where `props` is a list of atoms representing the requested properties.

  An empty body is treated as an allprop request per RFC 4918 Section 9.1.
  """
  def parse_propfind(body) when body in [nil, ""] do
    {:ok, :allprop}
  end

  def parse_propfind(body) do
    cond do
      String.contains?(body, "<d:allprop") or String.contains?(body, "<D:allprop") ->
        {:ok, :allprop}

      String.contains?(body, "<d:propname") or String.contains?(body, "<D:propname") ->
        {:ok, :propname}

      true ->
        props = extract_requested_props(body)
        {:ok, {:prop, props}}
    end
  end

  @doc """
  Extracts href elements from an addressbook-multiget REPORT body.

  Returns `{:ok, hrefs}` where hrefs is a list of URI strings.
  """
  def parse_addressbook_multiget(body) do
    hrefs =
      Regex.scan(~r/<[dD]:href[^>]*>([^<]+)<\/[dD]:href>/i, body)
      |> Enum.map(fn [_, href] -> String.trim(href) end)

    {:ok, hrefs}
  end

  @doc """
  Extracts the sync-token from a sync-collection REPORT body.

  Returns `{:ok, token}` where token may be nil for an initial sync.
  """
  def parse_sync_collection(body) do
    token =
      case Regex.run(~r/<[dD]:sync-token[^>]*>([^<]*)<\/[dD]:sync-token>/i, body) do
        [_, token] when token != "" -> token
        _ -> nil
      end

    {:ok, token}
  end

  # ── Private ────────────────────────────────────────────────────────────

  defp extract_requested_props(body) do
    checks = [
      {"displayname", :displayname},
      {"resourcetype", :resourcetype},
      {"getcontenttype", :getcontenttype},
      {"getetag", :getetag},
      {"getlastmodified", :getlastmodified},
      {"address-data", :address_data},
      {"getctag", :getctag},
      {"sync-token", :sync_token},
      {"current-user-principal", :current_user_principal},
      {"addressbook-home-set", :addressbook_home_set},
      {"supported-report-set", :supported_report_set},
      {"supported-address-data", :supported_address_data}
    ]

    for {needle, atom} <- checks,
        String.contains?(body, needle),
        do: atom
  end
end
