defmodule Kith.PetsTest do
  use Kith.DataCase, async: true

  import Kith.Factory

  alias Kith.Pets

  describe "list_pets/2" do
    test "returns pets for the contact scoped to account" do
      {account, _user} = setup_account()
      contact = insert(:contact, account: account)
      pet = insert(:pet, account: account, contact: contact)

      assert [returned] = Pets.list_pets(account.id, contact.id)
      assert returned.id == pet.id
    end

    test "does not return pets from another contact" do
      {account, _user} = setup_account()
      contact1 = insert(:contact, account: account)
      contact2 = insert(:contact, account: account)
      insert(:pet, account: account, contact: contact1)
      insert(:pet, account: account, contact: contact2)

      assert [pet] = Pets.list_pets(account.id, contact1.id)
      assert pet.contact_id == contact1.id
    end

    test "does not return pets from another account" do
      {account1, _user1} = setup_account()
      {account2, _user2} = setup_account()
      contact1 = insert(:contact, account: account1)
      contact2 = insert(:contact, account: account2)
      insert(:pet, account: account1, contact: contact1)
      insert(:pet, account: account2, contact: contact2)

      assert [pet] = Pets.list_pets(account1.id, contact1.id)
      assert pet.account_id == account1.id
    end

    test "orders pets by name ascending" do
      {account, _user} = setup_account()
      contact = insert(:contact, account: account)
      insert(:pet, account: account, contact: contact, name: "Zeus")
      insert(:pet, account: account, contact: contact, name: "Apollo")

      pets = Pets.list_pets(account.id, contact.id)
      assert [%{name: "Apollo"}, %{name: "Zeus"}] = pets
    end
  end

  describe "get_pet!/2" do
    test "returns a pet by id scoped to account" do
      {account, _user} = setup_account()
      contact = insert(:contact, account: account)
      pet = insert(:pet, account: account, contact: contact)

      fetched = Pets.get_pet!(account.id, pet.id)
      assert fetched.id == pet.id
    end

    test "raises for pet in another account" do
      {account1, _user1} = setup_account()
      {account2, _user2} = setup_account()
      contact = insert(:contact, account: account1)
      pet = insert(:pet, account: account1, contact: contact)

      assert_raise Ecto.NoResultsError, fn ->
        Pets.get_pet!(account2.id, pet.id)
      end
    end
  end

  describe "create_pet/2" do
    test "creates a pet with valid attrs" do
      {account, _user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "name" => "Max",
        "species" => "dog",
        "breed" => "Labrador",
        "contact_id" => contact.id
      }

      assert {:ok, pet} = Pets.create_pet(account.id, attrs)
      assert pet.name == "Max"
      assert pet.species == "dog"
      assert pet.breed == "Labrador"
      assert pet.account_id == account.id
    end

    test "fails without name" do
      {account, _user} = setup_account()

      assert {:error, changeset} = Pets.create_pet(account.id, %{})
      assert errors_on(changeset).name
    end

    test "fails with invalid species" do
      {account, _user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{"name" => "Rex", "species" => "dinosaur", "contact_id" => contact.id}
      assert {:error, changeset} = Pets.create_pet(account.id, attrs)
      assert errors_on(changeset).species
    end
  end

  describe "update_pet/2" do
    test "updates pet attributes" do
      {account, _user} = setup_account()
      contact = insert(:contact, account: account)
      pet = insert(:pet, account: account, contact: contact)

      assert {:ok, updated} = Pets.update_pet(pet, %{name: "New Name", breed: "Poodle"})
      assert updated.name == "New Name"
      assert updated.breed == "Poodle"
    end
  end

  describe "delete_pet/1" do
    test "deletes the pet" do
      {account, _user} = setup_account()
      contact = insert(:contact, account: account)
      pet = insert(:pet, account: account, contact: contact)

      assert {:ok, _} = Pets.delete_pet(pet)
      assert Pets.list_pets(account.id, contact.id) == []
    end
  end
end
