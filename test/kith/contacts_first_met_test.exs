defmodule Kith.ContactsFirstMetTest do
  use Kith.DataCase, async: true

  alias Kith.Contacts
  alias Kith.Contacts.Contact
  alias Kith.Repo

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup do
    user = user_fixture()
    account_id = user.account_id
    contact = contact_fixture(account_id)
    met_through = contact_fixture(account_id, %{first_name: "Sarah"})
    %{user: user, account_id: account_id, contact: contact, met_through: met_through}
  end

  describe "first_met_through_id validation" do
    test "accepts a contact from the same account", %{contact: contact, met_through: met_through} do
      {:ok, updated} = Contacts.update_contact(contact, %{first_met_through_id: met_through.id})
      assert updated.first_met_through_id == met_through.id
    end

    test "rejects a contact from a different account", %{contact: contact} do
      other_user = user_fixture()
      other_contact = contact_fixture(other_user.account_id, %{first_name: "Other"})

      {:error, changeset} =
        Contacts.update_contact(contact, %{first_met_through_id: other_contact.id})

      assert "must be a contact in the same account" in errors_on(changeset).first_met_through_id
    end

    test "rejects a nonexistent contact ID", %{contact: contact} do
      {:error, changeset} = Contacts.update_contact(contact, %{first_met_through_id: 999_999})
      assert "must be a contact in the same account" in errors_on(changeset).first_met_through_id
    end

    test "rejects self-reference (contact cannot be met through themselves)", %{contact: contact} do
      {:error, changeset} = Contacts.update_contact(contact, %{first_met_through_id: contact.id})
      assert "cannot reference the contact itself" in errors_on(changeset).first_met_through_id
    end

    test "allows nil (clearing the field)", %{contact: contact, met_through: met_through} do
      {:ok, _} = Contacts.update_contact(contact, %{first_met_through_id: met_through.id})
      {:ok, updated} = Contacts.update_contact(contact, %{first_met_through_id: nil})
      assert is_nil(updated.first_met_through_id)
    end

    test "skips validation when first_met_through_id is not changed", %{
      contact: contact,
      met_through: met_through
    } do
      {:ok, contact} = Contacts.update_contact(contact, %{first_met_through_id: met_through.id})
      {:ok, updated} = Contacts.update_contact(contact, %{first_name: "Updated"})
      assert updated.first_met_through_id == met_through.id
    end
  end

  describe "first_met fields round-trip" do
    test "stores and retrieves all first-met fields", %{
      contact: contact,
      met_through: met_through
    } do
      {:ok, updated} =
        Contacts.update_contact(contact, %{
          first_met_at: ~D[2020-06-15],
          first_met_year_unknown: true,
          first_met_where: "College",
          first_met_through_id: met_through.id,
          first_met_additional_info: "Met at orientation week",
          birthdate_year_unknown: false
        })

      reloaded = Repo.get!(Contact, updated.id)
      assert reloaded.first_met_at == ~D[2020-06-15]
      assert reloaded.first_met_year_unknown == true
      assert reloaded.first_met_where == "College"
      assert reloaded.first_met_through_id == met_through.id
      assert reloaded.first_met_additional_info == "Met at orientation week"
      assert reloaded.birthdate_year_unknown == false
    end
  end
end
