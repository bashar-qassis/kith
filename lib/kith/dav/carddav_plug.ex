defmodule Kith.DAV.CardDAVPlug do
  @moduledoc """
  CardDAV server implementation as a Phoenix Plug.

  Handles the WebDAV/CardDAV protocol methods (PROPFIND, REPORT, GET, PUT,
  DELETE, OPTIONS) to provide bidirectional contact sync with DAV clients
  such as Apple Contacts, DAVx5 (Android), and Thunderbird.

  ## URL structure

      /dav/                              — DAV root (discovery)
      /dav/principals/                   — user principal
      /dav/addressbooks/                 — addressbook home set
      /dav/addressbooks/default/         — default address book collection
      /dav/addressbooks/default/:uid.vcf — individual contact resource

  ## Authentication

  All requests require HTTP Basic Auth (via `Kith.DAV.Auth`).
  """

  import Plug.Conn

  alias Kith.Contacts
  alias Kith.Contacts.Contact
  alias Kith.DAV.{Auth, VCardAdapter, XMLBuilder, XMLParser}

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = Auth.require_auth(conn)
    if conn.halted, do: conn, else: route(conn)
  end

  # ── Routing ────────────────────────────────────────────────────────────

  defp route(conn) do
    path = conn.request_path |> String.trim_trailing("/")
    dispatch(conn, conn.method, path_segments(path))
  end

  defp dispatch(conn, "OPTIONS", _), do: handle_options(conn)
  defp dispatch(conn, "PROPFIND", ["dav"]), do: handle_root_propfind(conn)
  defp dispatch(conn, "PROPFIND", ["dav", "principals"]), do: handle_principal_propfind(conn)
  defp dispatch(conn, "PROPFIND", ["dav", "addressbooks"]), do: handle_home_propfind(conn)

  defp dispatch(conn, "PROPFIND", ["dav", "addressbooks", "default"]),
    do: handle_addressbook_propfind(conn)

  defp dispatch(conn, "PROPFIND", ["dav", "addressbooks", "default", _uid]),
    do: handle_contact_propfind(conn)

  defp dispatch(conn, "REPORT", ["dav", "addressbooks", "default"]), do: handle_report(conn)

  defp dispatch(conn, "GET", ["dav", "addressbooks", "default", uid]),
    do: handle_get_contact(conn, uid)

  defp dispatch(conn, "PUT", ["dav", "addressbooks", "default", uid]),
    do: handle_put_contact(conn, uid)

  defp dispatch(conn, "DELETE", ["dav", "addressbooks", "default", uid]),
    do: handle_delete_contact(conn, uid)

  defp dispatch(conn, _, _), do: send_resp(conn, 404, "Not Found")

  defp path_segments(path) do
    path |> String.split("/") |> Enum.reject(&(&1 == ""))
  end

  defp account_id(conn), do: conn.assigns.current_scope.account.id

  # ── OPTIONS ────────────────────────────────────────────────────────────

  defp handle_options(conn) do
    conn
    |> put_resp_header("dav", "1, 2, 3, addressbook")
    |> put_resp_header("allow", "OPTIONS, GET, PUT, DELETE, PROPFIND, REPORT")
    |> send_resp(200, "")
  end

  # ── Root PROPFIND ──────────────────────────────────────────────────────

  defp handle_root_propfind(conn) do
    xml =
      XMLBuilder.multistatus([
        XMLBuilder.response("/dav/", [
          XMLBuilder.propstat([
            XMLBuilder.current_user_principal("/dav/principals/"),
            XMLBuilder.resourcetype("<d:collection/>")
          ])
        ])
      ])

    send_dav_response(conn, 207, xml)
  end

  # ── Principal PROPFIND ─────────────────────────────────────────────────

  defp handle_principal_propfind(conn) do
    xml =
      XMLBuilder.multistatus([
        XMLBuilder.response("/dav/principals/", [
          XMLBuilder.propstat([
            XMLBuilder.resourcetype("<d:collection/><d:principal/>"),
            "<card:addressbook-home-set><d:href>/dav/addressbooks/</d:href></card:addressbook-home-set>"
          ])
        ])
      ])

    send_dav_response(conn, 207, xml)
  end

  # ── Home set PROPFIND ──────────────────────────────────────────────────

  defp handle_home_propfind(conn) do
    xml =
      XMLBuilder.multistatus([
        XMLBuilder.response("/dav/addressbooks/", [
          XMLBuilder.propstat([
            XMLBuilder.resourcetype("<d:collection/>"),
            XMLBuilder.displayname("Address Books")
          ])
        ]),
        XMLBuilder.response("/dav/addressbooks/default/", [
          XMLBuilder.propstat([
            XMLBuilder.resourcetype("<d:collection/><card:addressbook/>"),
            XMLBuilder.displayname("Kith Contacts"),
            XMLBuilder.supported_address_data()
          ])
        ])
      ])

    send_dav_response(conn, 207, xml)
  end

  # ── Address book PROPFIND ──────────────────────────────────────────────

  defp handle_addressbook_propfind(conn) do
    {:ok, body, conn} = read_body(conn)
    {:ok, _request_type} = XMLParser.parse_propfind(body)
    depth = get_req_header(conn, "depth") |> List.first("0")

    responses = [addressbook_response(conn)]

    responses =
      if depth != "0" do
        contacts = list_contacts_for_dav(conn)

        contact_responses =
          Enum.map(contacts, fn contact ->
            etag = compute_etag(contact)

            XMLBuilder.response(
              "/dav/addressbooks/default/kith-contact-#{contact.id}.vcf",
              [
                XMLBuilder.propstat([
                  XMLBuilder.getetag(etag),
                  XMLBuilder.getcontenttype("text/vcard; charset=utf-8"),
                  XMLBuilder.getlastmodified(contact.updated_at)
                ])
              ]
            )
          end)

        responses ++ contact_responses
      else
        responses
      end

    send_dav_response(conn, 207, XMLBuilder.multistatus(responses))
  end

  # ── Contact PROPFIND ───────────────────────────────────────────────────

  defp handle_contact_propfind(conn) do
    uid = List.last(path_segments(conn.request_path))

    case find_contact_by_uid(conn, uid) do
      nil ->
        send_resp(conn, 404, "Not Found")

      contact ->
        etag = compute_etag(contact)

        xml =
          XMLBuilder.multistatus([
            XMLBuilder.response(conn.request_path, [
              XMLBuilder.propstat([
                XMLBuilder.getetag(etag),
                XMLBuilder.getcontenttype("text/vcard; charset=utf-8"),
                XMLBuilder.getlastmodified(contact.updated_at)
              ])
            ])
          ])

        send_dav_response(conn, 207, xml)
    end
  end

  # ── REPORT ─────────────────────────────────────────────────────────────

  defp handle_report(conn) do
    {:ok, body, conn} = read_body(conn)

    cond do
      String.contains?(body, "addressbook-multiget") ->
        handle_multiget_report(conn, body)

      String.contains?(body, "sync-collection") ->
        handle_sync_collection_report(conn)

      true ->
        send_resp(conn, 400, "Unsupported REPORT type")
    end
  end

  defp handle_multiget_report(conn, body) do
    {:ok, hrefs} = XMLParser.parse_addressbook_multiget(body)

    responses =
      Enum.map(hrefs, fn href ->
        uid = href |> String.split("/") |> List.last()

        case find_contact_by_uid(conn, uid) do
          nil ->
            XMLBuilder.response(href, [
              XMLBuilder.propstat([], "HTTP/1.1 404 Not Found")
            ])

          contact ->
            vcard = VCardAdapter.contact_to_vcard(contact)
            etag = compute_etag(contact)

            XMLBuilder.response(href, [
              XMLBuilder.propstat([
                XMLBuilder.getetag(etag),
                XMLBuilder.getcontenttype("text/vcard; charset=utf-8"),
                XMLBuilder.address_data(vcard)
              ])
            ])
        end
      end)

    send_dav_response(conn, 207, XMLBuilder.multistatus(responses))
  end

  defp handle_sync_collection_report(conn) do
    contacts = list_contacts_for_dav(conn)

    responses =
      Enum.map(contacts, fn contact ->
        etag = compute_etag(contact)
        vcard = VCardAdapter.contact_to_vcard(contact)

        XMLBuilder.response(
          "/dav/addressbooks/default/kith-contact-#{contact.id}.vcf",
          [
            XMLBuilder.propstat([
              XMLBuilder.getetag(etag),
              XMLBuilder.address_data(vcard)
            ])
          ]
        )
      end)

    token = generate_sync_token()
    xml = XMLBuilder.multistatus(responses)

    # Append sync-token outside the multistatus body but visible to clients
    # that parse it from the response. For a complete implementation, embed
    # it inside the multistatus element.
    xml =
      String.replace(
        xml,
        "</d:multistatus>",
        "#{XMLBuilder.sync_token(token)}\n</d:multistatus>"
      )

    send_dav_response(conn, 207, xml)
  end

  # ── GET ────────────────────────────────────────────────────────────────

  defp handle_get_contact(conn, uid) do
    case find_contact_by_uid(conn, uid) do
      nil ->
        send_resp(conn, 404, "Not Found")

      contact ->
        vcard = VCardAdapter.contact_to_vcard(contact)
        etag = compute_etag(contact)

        conn
        |> put_resp_content_type("text/vcard")
        |> put_resp_header("etag", "\"#{etag}\"")
        |> send_resp(200, vcard)
    end
  end

  # ── PUT ────────────────────────────────────────────────────────────────

  defp handle_put_contact(conn, uid) do
    {:ok, body, conn} = read_body(conn)
    attrs = VCardAdapter.vcard_to_attrs(body)
    aid = account_id(conn)

    case find_contact_by_uid(conn, uid) do
      nil ->
        # Create new contact
        case Contacts.create_contact(aid, attrs) do
          {:ok, contact} ->
            etag = compute_etag(contact)

            conn
            |> put_resp_header("etag", "\"#{etag}\"")
            |> send_resp(201, "")

          {:error, _changeset} ->
            send_resp(conn, 422, "Invalid vCard data")
        end

      contact ->
        # Update existing contact
        case Contacts.update_contact(contact, attrs) do
          {:ok, updated} ->
            etag = compute_etag(updated)

            conn
            |> put_resp_header("etag", "\"#{etag}\"")
            |> send_resp(204, "")

          {:error, _changeset} ->
            send_resp(conn, 422, "Invalid vCard data")
        end
    end
  end

  # ── DELETE ─────────────────────────────────────────────────────────────

  defp handle_delete_contact(conn, uid) do
    case find_contact_by_uid(conn, uid) do
      nil ->
        send_resp(conn, 404, "Not Found")

      contact ->
        Contacts.soft_delete_contact(contact)
        send_resp(conn, 204, "")
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp find_contact_by_uid(conn, uid) do
    # UID format: "kith-contact-123.vcf"
    case Regex.run(~r/kith-contact-(\d+)\.vcf/, uid) do
      [_, id_str] ->
        Contacts.get_contact(account_id(conn), String.to_integer(id_str))

      _ ->
        nil
    end
  end

  defp list_contacts_for_dav(conn) do
    Contacts.list_contacts(account_id(conn))
  end

  defp compute_etag(%Contact{} = contact) do
    data = "#{contact.id}-#{DateTime.to_unix(contact.updated_at)}"

    :crypto.hash(:md5, data)
    |> Base.encode16(case: :lower)
  end

  defp generate_sync_token do
    "https://kith.app/ns/sync/#{DateTime.to_unix(DateTime.utc_now())}"
  end

  defp addressbook_response(conn) do
    # Use the latest contact's updated_at as CTag, or current time if none
    contacts = list_contacts_for_dav(conn)

    ctag =
      case contacts do
        [] ->
          DateTime.to_unix(DateTime.utc_now()) |> to_string()

        contacts ->
          contacts
          |> Enum.map(& &1.updated_at)
          |> Enum.max(DateTime)
          |> DateTime.to_unix()
          |> to_string()
      end

    XMLBuilder.response("/dav/addressbooks/default/", [
      XMLBuilder.propstat([
        XMLBuilder.resourcetype("<d:collection/><card:addressbook/>"),
        XMLBuilder.displayname("Kith Contacts"),
        XMLBuilder.getctag(ctag),
        XMLBuilder.supported_address_data(),
        supported_report_set()
      ])
    ])
  end

  defp supported_report_set do
    "<d:supported-report-set>" <>
      "<d:supported-report><d:report><card:addressbook-multiget/></d:report></d:supported-report>" <>
      "<d:supported-report><d:report><d:sync-collection/></d:report></d:supported-report>" <>
      "</d:supported-report-set>"
  end

  defp send_dav_response(conn, status, xml) do
    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("dav", "1, 2, 3, addressbook")
    |> send_resp(status, xml)
  end
end
