defmodule KithWeb.DAV.AccessControlTest do
  @moduledoc """
  Account-scoped access control (multitenancy), method routing,
  and end-to-end client workflow tests.
  """
  use KithWeb.ConnCase, async: true

  import KithWeb.DAV.TestHelpers

  alias Kith.AccountsFixtures
  alias Kith.ContactsFixtures

  # ═══════════════════════════════════════════════════════════════════════════
  # Multitenancy isolation
  # ═══════════════════════════════════════════════════════════════════════════

  describe "account-scoped access control (multitenancy)" do
    setup do
      user_a = AccountsFixtures.user_fixture()
      user_b = AccountsFixtures.user_fixture()
      %{conn: build_conn(), user_a: user_a, user_b: user_b}
    end

    test "principal A MUST NOT see principal B's address objects in PROPFIND",
         %{conn: conn, user_a: user_a, user_b: user_b} do
      contact_b =
        ContactsFixtures.contact_fixture(user_b.account.id, %{first_name: "SecretBob"})

      resp =
        conn
        |> basic_auth(user_a.email, dav_password())
        |> put_req_header("depth", "1")
        |> dav_request("PROPFIND", "/dav/addressbooks/default/", propfind_body())

      refute resp.resp_body =~ "kith-contact-#{contact_b.id}.vcf"
    end

    test "principal A MUST NOT be able to GET principal B's address object",
         %{conn: conn, user_a: user_a, user_b: user_b} do
      contact_b = ContactsFixtures.contact_fixture(user_b.account.id)

      resp =
        conn
        |> basic_auth(user_a.email, dav_password())
        |> dav_request("GET", contact_path(contact_b))

      assert resp.status == 404
    end

    test "principal A MUST NOT be able to DELETE principal B's address object",
         %{conn: conn, user_a: user_a, user_b: user_b} do
      contact_b = ContactsFixtures.contact_fixture(user_b.account.id)

      resp =
        conn
        |> basic_auth(user_a.email, dav_password())
        |> dav_request("DELETE", contact_path(contact_b))

      assert resp.status == 404

      resp_b =
        build_conn()
        |> basic_auth(user_b.email, dav_password())
        |> dav_request("GET", contact_path(contact_b))

      assert resp_b.status == 200
    end

    test "principal A MUST NOT be able to PUT to principal B's address object",
         %{conn: conn, user_a: user_a, user_b: user_b} do
      contact_b = ContactsFixtures.contact_fixture(user_b.account.id)
      vcard = build_vcard("Hacked", "Contact")

      resp =
        conn
        |> basic_auth(user_a.email, dav_password())
        |> dav_request("PUT", contact_path(contact_b), vcard)

      # find_contact_by_uid scopes by account_id, so user_a can't find user_b's contact.
      # A new contact is created under user_a's account instead — not a cross-account write.
      assert resp.status in [201, 404]

      # Verify user_b's contact was NOT modified
      resp_b =
        build_conn()
        |> basic_auth(user_b.email, dav_password())
        |> dav_request("GET", contact_path(contact_b))

      assert resp_b.status == 200
      refute resp_b.resp_body =~ "Hacked"
    end

    test "principal A MUST NOT see principal B's contacts in multiget REPORT",
         %{conn: conn, user_a: user_a, user_b: user_b} do
      contact_b =
        ContactsFixtures.contact_fixture(user_b.account.id, %{first_name: "SecretData"})

      body = multiget_body([contact_path(contact_b)])

      resp =
        conn
        |> basic_auth(user_a.email, dav_password())
        |> dav_request("REPORT", "/dav/addressbooks/default/", body)

      assert resp.status == 207
      assert resp.resp_body =~ "404 Not Found"
      refute resp.resp_body =~ "SecretData"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RFC 4918 — Method routing
  # ═══════════════════════════════════════════════════════════════════════════

  describe "RFC 4918 — method routing" do
    setup :setup_dav_user

    test "unknown paths MUST return 404", context do
      conn = authed_dav(context, "GET", "/dav/nonexistent/path")
      assert conn.status == 404
    end

    test "unimplemented methods MUST return appropriate error", context do
      conn = authed_dav(context, "POST", "/dav/addressbooks/default/")
      assert conn.status in [404, 405]
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # End-to-end client workflow
  # ═══════════════════════════════════════════════════════════════════════════

  describe "end-to-end CardDAV client workflow" do
    setup :setup_dav_user

    test "complete CRUD lifecycle as a DAV client would perform it", context do
      # 1. PUT to create (RFC 6352 §5.1)
      vcard = build_vcard("Lifecycle", "Test", email: "lifecycle@example.com")

      conn1 =
        authed_dav(context, "PUT", "/dav/addressbooks/default/kith-contact-999999.vcf", vcard)

      assert conn1.status == 201

      # 2. PROPFIND to discover (RFC 4918 §9.1)
      conn2 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> put_req_header("depth", "1")
        |> dav_request("PROPFIND", "/dav/addressbooks/default/", propfind_body())

      [[_, id_str]] = Regex.scan(~r{kith-contact-(\d+)\.vcf}, conn2.resp_body)
      resource_path = "/dav/addressbooks/default/kith-contact-#{id_str}.vcf"

      # 3. GET to retrieve (RFC 6352 §8.6)
      conn3 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", resource_path)

      assert conn3.status == 200
      assert conn3.resp_body =~ "Lifecycle"
      [etag_v1] = get_resp_header(conn3, "etag")

      # 4. PUT to update (RFC 6352 §5.1)
      Process.sleep(1000)
      updated = build_vcard("Updated", "Lifecycle", company: "NewCo")

      conn4 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("PUT", resource_path, updated)

      assert conn4.status == 204
      [etag_v2] = get_resp_header(conn4, "etag")
      assert etag_v1 != etag_v2

      # 5. GET to verify update
      conn5 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", resource_path)

      assert conn5.status == 200
      assert conn5.resp_body =~ "Updated"
      assert conn5.resp_body =~ "NewCo"

      # 6. DELETE (RFC 4918 §9.6)
      conn6 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("DELETE", resource_path)

      assert conn6.status == 204

      # 7. GET MUST return 404 after deletion
      conn7 =
        build_conn()
        |> basic_auth(context.user.email, dav_password())
        |> dav_request("GET", resource_path)

      assert conn7.status == 404
    end
  end
end
