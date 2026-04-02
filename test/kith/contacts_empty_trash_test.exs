defmodule Kith.Contacts.EmptyTrashTest do
  use Kith.DataCase

  alias Kith.Contacts
  alias Kith.ContactsFixtures
  alias Kith.AccountsFixtures

  setup do
    ContactsFixtures.seed_reference_data!()
    user = AccountsFixtures.user_fixture()
    %{account_id: user.account_id}
  end

  describe "empty_trash/1" do
    @tag :integration
    test "returns {:ok, count} and permanently deletes all trashed contacts", ctx do
      # Create two contacts then soft-delete them
      c1 = ContactsFixtures.contact_fixture(ctx.account_id)
      c2 = ContactsFixtures.contact_fixture(ctx.account_id)

      {:ok, _} = Contacts.soft_delete_contact(c1)
      {:ok, _} = Contacts.soft_delete_contact(c2)

      assert {:ok, 2} = Contacts.empty_trash(ctx.account_id)

      # Both must be gone from DB entirely (not just soft-deleted)
      assert Repo.get(Kith.Contacts.Contact, c1.id) == nil
      assert Repo.get(Kith.Contacts.Contact, c2.id) == nil
    end

    @tag :integration
    test "returns {:ok, 0} when trash is already empty", ctx do
      assert {:ok, 0} = Contacts.empty_trash(ctx.account_id)
    end

    @tag :integration
    test "does not delete active (non-trashed) contacts", ctx do
      active = ContactsFixtures.contact_fixture(ctx.account_id)
      trashed = ContactsFixtures.contact_fixture(ctx.account_id)

      {:ok, _} = Contacts.soft_delete_contact(trashed)

      assert {:ok, 1} = Contacts.empty_trash(ctx.account_id)

      # Active contact must still exist
      assert Repo.get(Kith.Contacts.Contact, active.id) != nil
      # Trashed contact must be gone
      assert Repo.get(Kith.Contacts.Contact, trashed.id) == nil
    end

    @tag :integration
    test "only deletes contacts belonging to the given account", ctx do
      other_user = AccountsFixtures.user_fixture()
      other_account_id = other_user.account_id

      # Trash a contact in the primary account
      mine = ContactsFixtures.contact_fixture(ctx.account_id)
      {:ok, _} = Contacts.soft_delete_contact(mine)

      # Trash a contact in a different account
      theirs = ContactsFixtures.contact_fixture(other_account_id)
      {:ok, _} = Contacts.soft_delete_contact(theirs)

      # Empty only the primary account's trash
      assert {:ok, 1} = Contacts.empty_trash(ctx.account_id)

      # Other account's trashed contact must remain in DB
      assert Repo.get(Kith.Contacts.Contact, theirs.id) != nil
    end
  end
end
