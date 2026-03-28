defmodule Kith.ContactsDAVTest do
  @moduledoc "Unit tests for DAV-related Contacts context functions."
  use Kith.DataCase, async: true

  alias Kith.Contacts

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup do
    seed_reference_data!()
    user = user_fixture()
    account_id = user.account_id
    contact = contact_fixture(account_id)
    %{account_id: account_id, contact: contact}
  end

  describe "replace_contact_children/3" do
    test "replaces existing children with new data", %{contact: contact, account_id: aid} do
      nested = %{
        emails: [%{value: "old@example.com", label: "Home"}],
        phones: [],
        urls: [],
        addresses: []
      }

      assert {:ok, :ok} = Contacts.replace_contact_children(contact, aid, nested)

      # Replace with new data
      nested2 = %{
        emails: [%{value: "new@example.com", label: "Work"}],
        phones: [%{value: "555-1234", label: "Mobile"}],
        urls: [],
        addresses: []
      }

      assert {:ok, :ok} = Contacts.replace_contact_children(contact, aid, nested2)

      # Verify old email is gone and new data is present
      contact = Kith.Repo.preload(contact, [contact_fields: :contact_field_type], force: true)
      values = Enum.map(contact.contact_fields, & &1.value)
      assert "new@example.com" in values
      assert "555-1234" in values
      refute "old@example.com" in values
    end

    test "handles empty lists", %{contact: contact, account_id: aid} do
      nested = %{emails: [], phones: [], urls: [], addresses: []}
      assert {:ok, :ok} = Contacts.replace_contact_children(contact, aid, nested)
    end

    test "replaces children with address data", %{contact: contact, account_id: aid} do
      nested = %{
        emails: [%{value: "addr@example.com", label: "Work"}],
        phones: [],
        urls: [],
        addresses: [
          %{
            label: "Home",
            line1: "123 Main St",
            city: "Springfield",
            province: "IL",
            postal_code: "62701",
            country: "US"
          }
        ]
      }

      assert {:ok, :ok} = Contacts.replace_contact_children(contact, aid, nested)

      contact =
        Kith.Repo.preload(contact, [:addresses, contact_fields: :contact_field_type], force: true)

      assert length(contact.addresses) == 1
      assert hd(contact.addresses).line1 == "123 Main St"
      assert hd(contact.addresses).city == "Springfield"

      values = Enum.map(contact.contact_fields, & &1.value)
      assert "addr@example.com" in values
    end
  end

  describe "touch_contact!/1" do
    test "bumps updated_at", %{contact: contact} do
      old_updated_at = contact.updated_at
      # Ensure at least 1 second passes
      Process.sleep(1100)
      updated = Contacts.touch_contact!(contact)
      assert DateTime.compare(updated.updated_at, old_updated_at) == :gt
    end
  end

  describe "list_contacts_modified_since/2" do
    test "returns contacts modified after the given timestamp", %{
      account_id: aid,
      contact: contact
    } do
      # Contact was just created, so its updated_at is recent
      past = DateTime.add(contact.updated_at, -1, :second)
      assert [found] = Contacts.list_contacts_modified_since(aid, past)
      assert found.id == contact.id
    end

    test "excludes contacts at exactly the timestamp (strict >)", %{
      account_id: aid,
      contact: contact
    } do
      assert [] = Contacts.list_contacts_modified_since(aid, contact.updated_at)
    end

    test "excludes soft-deleted contacts", %{account_id: aid, contact: contact} do
      Contacts.soft_delete_contact(contact)
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      results = Contacts.list_contacts_modified_since(aid, past)
      refute Enum.any?(results, &(&1.id == contact.id))
    end
  end

  describe "list_contacts_deleted_since/2" do
    test "returns soft-deleted contacts after the given timestamp", %{
      account_id: aid,
      contact: contact
    } do
      past = DateTime.add(DateTime.utc_now(), -1, :second)
      Contacts.soft_delete_contact(contact)
      assert [found] = Contacts.list_contacts_deleted_since(aid, past)
      assert found.id == contact.id
    end

    test "excludes contacts at exactly the timestamp (strict >)", %{
      account_id: aid,
      contact: contact
    } do
      Contacts.soft_delete_contact(contact)
      deleted = Kith.Repo.get!(Contacts.Contact, contact.id)
      assert [] = Contacts.list_contacts_deleted_since(aid, deleted.deleted_at)
    end

    test "excludes active (non-deleted) contacts", %{account_id: aid} do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      assert [] = Contacts.list_contacts_deleted_since(aid, past)
    end
  end
end
