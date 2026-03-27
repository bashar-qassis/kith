defmodule KithWeb.DAV.ReportTest do
  @moduledoc """
  RFC 6352 §8.7 — addressbook-multiget REPORT
  RFC 6578 §3  — sync-collection REPORT
  """
  use KithWeb.ConnCase, async: true

  import KithWeb.DAV.TestHelpers

  alias Kith.Contacts
  alias Kith.ContactsFixtures

  setup :setup_dav_user

  # ── RFC 6352 §8.7 — addressbook-multiget ────────────────────────────────

  describe "RFC 6352 §8.7 — addressbook-multiget REPORT" do
    test "MUST return 207 Multi-Status with response for each requested href",
         %{account_id: account_id} = context do
      c1 = ContactsFixtures.contact_fixture(account_id, %{first_name: "Alice"})
      c2 = ContactsFixtures.contact_fixture(account_id, %{first_name: "Bob"})
      _c3 = ContactsFixtures.contact_fixture(account_id, %{first_name: "Charlie"})

      body = multiget_body([contact_path(c1), contact_path(c2)])
      conn = authed_dav(context, "REPORT", "/dav/addressbooks/default/", body)

      assert conn.status == 207
      assert count_responses(conn.resp_body) == 2
    end

    test "MUST return address-data containing the vCard for each found resource",
         %{account_id: account_id} = context do
      contact =
        ContactsFixtures.contact_fixture(account_id, %{first_name: "Zara", last_name: "Quinn"})

      body = multiget_body([contact_path(contact)])
      conn = authed_dav(context, "REPORT", "/dav/addressbooks/default/", body)

      assert conn.resp_body =~ "address-data"
      assert conn.resp_body =~ "BEGIN:VCARD"
      assert conn.resp_body =~ "Zara"
      assert conn.resp_body =~ "Quinn"
    end

    test "MUST include getetag in each response", %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)

      body = multiget_body([contact_path(contact)])
      conn = authed_dav(context, "REPORT", "/dav/addressbooks/default/", body)

      assert conn.resp_body =~ "getetag"
    end

    test "MUST return 404 status for inaccessible/missing resources in multiget",
         %{account_id: account_id} = context do
      contact = ContactsFixtures.contact_fixture(account_id)
      missing = "/dav/addressbooks/default/kith-contact-999999.vcf"

      body = multiget_body([contact_path(contact), missing])
      conn = authed_dav(context, "REPORT", "/dav/addressbooks/default/", body)

      assert conn.status == 207
      assert conn.resp_body =~ "404 Not Found"
    end
  end

  # ── RFC 6578 §3 — sync-collection ──────────────────────────────────────

  describe "RFC 6578 §3 — sync-collection REPORT" do
    test "MUST return 207 Multi-Status with all current members",
         %{account_id: account_id} = context do
      ContactsFixtures.contact_fixture(account_id, %{first_name: "Alice"})
      ContactsFixtures.contact_fixture(account_id, %{first_name: "Bob"})

      conn =
        authed_dav(context, "REPORT", "/dav/addressbooks/default/", sync_collection_body())

      assert conn.status == 207
      assert conn.resp_body =~ "Alice"
      assert conn.resp_body =~ "Bob"
    end

    test "response MUST include sync-token that is a valid URI (RFC 6578 §4)",
         %{account_id: account_id} = context do
      ContactsFixtures.contact_fixture(account_id)

      conn =
        authed_dav(context, "REPORT", "/dav/addressbooks/default/", sync_collection_body())

      assert conn.resp_body =~ "sync-token"

      [token] =
        Regex.run(~r/<d:sync-token>([^<]+)<\/d:sync-token>/, conn.resp_body,
          capture: :all_but_first
        )

      assert token =~ ~r{^https?://}
    end

    test "each member response MUST include getetag and address-data",
         %{account_id: account_id} = context do
      ContactsFixtures.contact_fixture(account_id)

      conn =
        authed_dav(context, "REPORT", "/dav/addressbooks/default/", sync_collection_body())

      assert conn.resp_body =~ "getetag"
      assert conn.resp_body =~ "address-data"
      assert conn.resp_body =~ "BEGIN:VCARD"
    end

    test "MUST NOT include deleted or archived members",
         %{account_id: account_id} = context do
      ContactsFixtures.contact_fixture(account_id, %{first_name: "Active"})
      archived = ContactsFixtures.contact_fixture(account_id, %{first_name: "Archived"})
      deleted = ContactsFixtures.contact_fixture(account_id, %{first_name: "Deleted"})
      {:ok, _} = Contacts.archive_contact(archived)
      {:ok, _} = Contacts.soft_delete_contact(deleted)

      conn =
        authed_dav(context, "REPORT", "/dav/addressbooks/default/", sync_collection_body())

      assert conn.resp_body =~ "Active"
      refute conn.resp_body =~ "kith-contact-#{archived.id}.vcf"
      refute conn.resp_body =~ "kith-contact-#{deleted.id}.vcf"
    end
  end

  # ── Unsupported REPORT types ────────────────────────────────────────────

  describe "RFC 6352 — unsupported REPORT types" do
    test "server MUST return 400 for unrecognized REPORT type", context do
      body = """
      <?xml version="1.0" encoding="UTF-8"?>
      <d:unknown-report xmlns:d="DAV:"/>
      """

      conn = authed_dav(context, "REPORT", "/dav/addressbooks/default/", body)
      assert conn.status == 400
    end
  end
end
