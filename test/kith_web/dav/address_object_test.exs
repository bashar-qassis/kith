defmodule KithWeb.DAV.AddressObjectTest do
  @moduledoc """
  RFC 6352 §8.6 — GET address object resource
  RFC 2426     — vCard 3.0 format requirements
  RFC 6352 §5.1 — PUT to create/update address objects
  RFC 4918 §9.6 — DELETE address objects
  RFC 7232 §2.3 — ETag format and behavior
  """
  use KithWeb.ConnCase, async: true

  import Kith.Factory
  import KithWeb.DAV.TestHelpers

  alias Kith.Contacts
  alias Kith.ContactsFixtures

  setup :setup_dav_user

  # ═══════════════════════════════════════════════════════════════════════════
  # RFC 6352 §8.6 — GET address object resource
  # ═══════════════════════════════════════════════════════════════════════════

  describe "RFC 6352 §8.6 — GET address object resource" do
    test "Content-Type MUST be text/vcard (RFC 6352 §5.1)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/vcard"
    end

    test "response MUST include ETag header (RFC 6352 §5.1)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      conn = authed_dav(context, "GET", contact_path(contact))

      [etag] = get_resp_header(conn, "etag")
      assert etag != ""
    end

    test "ETag MUST be a quoted string (RFC 7232 §2.3)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      conn = authed_dav(context, "GET", contact_path(contact))

      [etag] = get_resp_header(conn, "etag")
      assert Regex.match?(~r/^(W\/)?"[^"]*"$/, etag)
    end

    test "MUST return 404 for non-existent address object", context do
      conn =
        authed_dav(context, "GET", "/dav/addressbooks/default/kith-contact-999999.vcf")

      assert conn.status == 404
    end

    test "MUST return 404 for deleted address object",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      {:ok, _} = Contacts.soft_delete_contact(contact)

      conn = authed_dav(context, "GET", contact_path(contact))
      assert conn.status == 404
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RFC 2426 — vCard 3.0 format in GET response
  # ═══════════════════════════════════════════════════════════════════════════

  describe "RFC 2426 — vCard 3.0 format in GET response" do
    test "body MUST begin with BEGIN:VCARD and end with END:VCARD",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      conn = authed_dav(context, "GET", contact_path(contact))

      body = conn.resp_body
      assert String.starts_with?(body, "BEGIN:VCARD")
      assert body |> String.trim_trailing() |> String.ends_with?("END:VCARD")
    end

    test "vCard MUST contain VERSION:3.0 property", %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ "VERSION:3.0"
    end

    test "vCard MUST contain FN (formatted name) property (RFC 2426 §3.1.1)",
         %{account_id: account_id} = context do
      contact =
        ContactsFixtures.contact_fixture(account_id, %{first_name: "Zara", last_name: "Quinn"})

      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ ~r/^FN:/m
      assert conn.resp_body =~ "Zara"
    end

    test "vCard MUST contain N (structured name) property (RFC 2426 §3.1.2)",
         %{account_id: account_id} = context do
      contact =
        ContactsFixtures.contact_fixture(account_id, %{first_name: "Zara", last_name: "Quinn"})

      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ ~r/^N:/m
    end

    test "vCard MUST contain UID property for CardDAV (RFC 6352 §6.3.2)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ ~r/^UID:/m
    end

    test "vCard MUST include BDAY when contact has birthdate",
         %{account_id: account_id} = context do
      contact =
        ContactsFixtures.contact_fixture(account_id, %{
          first_name: "Alice",
          birthdate: ~D[1990-06-15]
        })

      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ "BDAY:1990-06-15"
    end

    test "vCard MUST include ORG when contact has company",
         %{account_id: account_id} = context do
      contact =
        ContactsFixtures.contact_fixture(account_id, %{
          first_name: "Alice",
          company: "Acme Corp"
        })

      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ ~r/^ORG:/m
      assert conn.resp_body =~ "Acme Corp"
    end

    test "vCard MUST include ADR when contact has addresses",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id, %{first_name: "Alice"})

      ContactsFixtures.address_fixture(contact, %{
        "label" => "Home",
        "line1" => "123 Main St",
        "city" => "Springfield"
      })

      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ ~r/^ADR/m
      assert conn.resp_body =~ "123 Main St"
      assert conn.resp_body =~ "Springfield"
    end

    test "vCard MUST include EMAIL when contact has email fields",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id, %{first_name: "Alice"})
      email_type = insert(:contact_field_type, protocol: "mailto", vcard_label: "EMAIL")

      ContactsFixtures.contact_field_fixture(contact, email_type.id, %{
        "value" => "alice@example.com"
      })

      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ ~r/^EMAIL/m
      assert conn.resp_body =~ "alice@example.com"
    end

    test "vCard MUST include TEL when contact has phone fields",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id, %{first_name: "Alice"})
      tel_type = insert(:contact_field_type, protocol: "tel", vcard_label: "TEL")

      ContactsFixtures.contact_field_fixture(contact, tel_type.id, %{
        "value" => "+1-555-0123"
      })

      conn = authed_dav(context, "GET", contact_path(contact))

      assert conn.resp_body =~ ~r/^TEL/m
      assert conn.resp_body =~ "+1-555-0123"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RFC 6352 §5.1 — PUT to create new address object
  # ═══════════════════════════════════════════════════════════════════════════

  describe "RFC 6352 §5.1 — PUT to create new address object" do
    test "MUST return 201 Created when resource is new", context do
      vcard = build_vcard("New", "Contact")

      conn =
        authed_dav(context, "PUT", "/dav/addressbooks/default/kith-contact-999999.vcf", vcard)

      assert conn.status == 201
    end

    test "response MUST include ETag header on creation (RFC 6352 §5.1)", context do
      vcard = build_vcard("New", "Contact")

      conn =
        authed_dav(context, "PUT", "/dav/addressbooks/default/kith-contact-999999.vcf", vcard)

      assert conn.status == 201
      assert get_resp_header(conn, "etag") != []
    end

    test "created resource MUST be retrievable via GET", context do
      vcard = build_vcard("Created", "ViaDAV", nickname: "Davy")

      conn1 =
        authed_dav(context, "PUT", "/dav/addressbooks/default/kith-contact-999999.vcf", vcard)

      assert conn1.status == 201

      conn2 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("depth", "1")
        |> dav_request("PROPFIND", "/dav/addressbooks/default/", propfind_body())

      [[_, id_str]] = Regex.scan(~r{kith-contact-(\d+)\.vcf}, conn2.resp_body)

      conn3 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", "/dav/addressbooks/default/kith-contact-#{id_str}.vcf")

      assert conn3.status == 200
      assert conn3.resp_body =~ "Created"
      assert conn3.resp_body =~ "ViaDAV"
    end

    test "server MUST reject vCard missing required properties (first_name)", context do
      invalid = "BEGIN:VCARD\r\nVERSION:3.0\r\nNOTE:no name\r\nEND:VCARD\r\n"

      conn =
        authed_dav(context, "PUT", "/dav/addressbooks/default/kith-contact-999999.vcf", invalid)

      assert conn.status in 400..499
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RFC 6352 §5.1 — PUT to update existing address object
  # ═══════════════════════════════════════════════════════════════════════════

  describe "RFC 6352 §5.1 — PUT to update existing address object" do
    test "MUST return 204 No Content when resource already exists",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id, %{first_name: "Original"})
      vcard = build_vcard("Updated", "Name")

      conn = authed_dav(context, "PUT", contact_path(contact), vcard)

      assert conn.status == 204
    end

    test "response MUST include updated ETag header (RFC 6352 §5.1)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      vcard = build_vcard("Updated", "Contact")

      conn = authed_dav(context, "PUT", contact_path(contact), vcard)

      assert get_resp_header(conn, "etag") != []
    end

    test "updated properties MUST be reflected in subsequent GET",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id, %{first_name: "Original"})
      vcard = build_vcard("Modified", "Person", company: "NewCorp")

      conn1 = authed_dav(context, "PUT", contact_path(contact), vcard)
      assert conn1.status == 204

      conn2 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", contact_path(contact))

      assert conn2.status == 200
      assert conn2.resp_body =~ "Modified"
      assert conn2.resp_body =~ "Person"
      assert conn2.resp_body =~ "NewCorp"
    end

    test "ETag MUST change after successful update (RFC 7232 §2.3)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id, %{first_name: "Original"})

      conn1 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", contact_path(contact))

      [etag_before] = get_resp_header(conn1, "etag")

      Process.sleep(1000)
      vcard = build_vcard("Updated", "Name")
      conn2 = authed_dav(context, "PUT", contact_path(contact), vcard)
      [etag_after] = get_resp_header(conn2, "etag")

      assert etag_before != etag_after
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RFC 4918 §9.6 — DELETE address object
  # ═══════════════════════════════════════════════════════════════════════════

  describe "RFC 4918 §9.6 — DELETE address object" do
    test "MUST return 204 No Content on successful deletion",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      conn = authed_dav(context, "DELETE", contact_path(contact))

      assert conn.status == 204
    end

    test "deleted resource MUST return 404 on subsequent GET",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)

      conn1 = authed_dav(context, "DELETE", contact_path(contact))
      assert conn1.status == 204

      conn2 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", contact_path(contact))

      assert conn2.status == 404
    end

    test "deleted resource MUST NOT appear in collection listing",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      authed_dav(context, "DELETE", contact_path(contact))

      conn =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("depth", "1")
        |> dav_request("PROPFIND", "/dav/addressbooks/default/", propfind_body())

      refute conn.resp_body =~ "kith-contact-#{contact.id}.vcf"
    end

    test "MUST return 404 when deleting non-existent resource", context do
      conn =
        authed_dav(context, "DELETE", "/dav/addressbooks/default/kith-contact-999999.vcf")

      assert conn.status == 404
    end
  end

  # ── RFC 7232 §3 — Conditional requests (If-Match / If-None-Match) ─────

  describe "RFC 7232 §3 — conditional requests" do
    test "PUT with correct If-Match succeeds (204)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      # GET to retrieve ETag
      conn_get = authed_dav(context, "GET", contact_path(contact))
      [etag] = get_resp_header(conn_get, "etag")

      vcard = build_vcard("Updated", "Person")

      conn =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("if-match", etag)
        |> dav_request("PUT", contact_path(contact), vcard)

      assert conn.status == 204
    end

    test "PUT with wrong If-Match returns 412 Precondition Failed",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      vcard = build_vcard("Updated", "Person")

      conn =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("if-match", "\"stale-etag-value\"")
        |> dav_request("PUT", contact_path(contact), vcard)

      assert conn.status == 412
    end

    test "PUT without If-Match header proceeds normally",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      vcard = build_vcard("Updated", "Person")
      conn = authed_dav(context, "PUT", contact_path(contact), vcard)
      assert conn.status == 204
    end

    test "DELETE with correct If-Match succeeds (204)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      conn_get = authed_dav(context, "GET", contact_path(contact))
      [etag] = get_resp_header(conn_get, "etag")

      conn =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("if-match", etag)
        |> dav_request("DELETE", contact_path(contact))

      assert conn.status == 204
    end

    test "DELETE with wrong If-Match returns 412",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)

      conn =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("if-match", "\"stale-etag\"")
        |> dav_request("DELETE", contact_path(contact))

      assert conn.status == 412
    end
  end

  # ── Round-trip contact fields via PUT/GET ──────────────────────────────

  describe "PUT/GET round-trip for contact fields" do
    test "PUT vCard with email and phone, GET returns them",
         context do
      vcard =
        build_vcard("Jane", "Doe",
          email: "jane@example.com",
          phone: "+15551234567"
        )

      path = "/dav/addressbooks/default/kith-contact-new-1.vcf"
      conn = authed_dav(context, "PUT", path, vcard)
      assert conn.status == 201

      # The server assigns its own UID, so we need to find the contact
      # via PROPFIND to get its actual path
      conn_list =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("depth", "1")
        |> dav_request("PROPFIND", "/dav/addressbooks/default/", propfind_body())

      # Extract the contact href from PROPFIND response
      [href] =
        Regex.scan(
          ~r{<d:href>(/dav/addressbooks/default/kith-contact-\d+\.vcf)</d:href>},
          conn_list.resp_body,
          capture: :all_but_first
        )
        |> List.flatten()

      conn_get =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", href)

      assert conn_get.status == 200
      assert conn_get.resp_body =~ "jane@example.com"
      assert conn_get.resp_body =~ "+15551234567"
    end

    test "PUT update replaces contact fields (not appends)",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)

      # First PUT with one email
      vcard1 = build_vcard("Jane", "Doe", email: "old@example.com")
      conn1 = authed_dav(context, "PUT", contact_path(contact), vcard1)
      assert conn1.status == 204

      # Second PUT with different email
      vcard2 = build_vcard("Jane", "Doe", email: "new@example.com")

      conn2 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("PUT", contact_path(contact), vcard2)

      assert conn2.status == 204

      # GET should show only the new email, not both
      conn_get =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", contact_path(contact))

      assert conn_get.resp_body =~ "new@example.com"
      refute conn_get.resp_body =~ "old@example.com"
    end
  end

  # ── RFC 6352 §5.1 — PUT Content-Type validation ───────────────────────

  describe "RFC 6352 §5.1 — PUT Content-Type validation" do
    test "PUT with wrong Content-Type returns 415 Unsupported Media Type", context do
      conn =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("content-type", "application/json")
        |> dispatch(
          KithWeb.Endpoint,
          "PUT",
          "/dav/addressbooks/default/kith-contact-new.vcf",
          "{}"
        )

      assert conn.status == 415
    end

    test "PUT with invalid vCard body returns 422 with precondition error", context do
      conn =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("content-type", "text/vcard")
        |> dispatch(
          KithWeb.Endpoint,
          "PUT",
          "/dav/addressbooks/default/kith-contact-new.vcf",
          "not a vcard"
        )

      assert conn.status == 422
      assert conn.resp_body =~ "valid-address-data"
    end
  end

  # ── RFC 2426 §2.6 — vCard line folding ─────────────────────────────────

  describe "RFC 2426 §2.6 — vCard line folding" do
    test "vCard lines longer than 75 octets are folded",
         %{account_id: account_id} = context do
      long_desc = String.duplicate("A", 200)

      contact =
        ContactsFixtures.contact_fixture(account_id, %{
          first_name: "Test",
          description: long_desc
        })

      conn = authed_dav(context, "GET", contact_path(contact))
      assert conn.status == 200
      # Folded lines have CRLF followed by a space
      assert conn.resp_body =~ "\r\n "
    end
  end
end
