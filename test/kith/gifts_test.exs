defmodule Kith.GiftsTest do
  use Kith.DataCase, async: true

  import Kith.Factory

  alias Kith.Gifts

  describe "list_gifts/2" do
    test "returns gifts for the contact scoped to account" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      gift = insert(:gift, account: account, contact: contact, creator: user)

      assert [returned] = Gifts.list_gifts(account.id, contact.id)
      assert returned.id == gift.id
    end

    test "does not return gifts from another contact" do
      {account, user} = setup_account()
      contact1 = insert(:contact, account: account)
      contact2 = insert(:contact, account: account)
      insert(:gift, account: account, contact: contact1, creator: user)
      insert(:gift, account: account, contact: contact2, creator: user)

      assert [gift] = Gifts.list_gifts(account.id, contact1.id)
      assert gift.contact_id == contact1.id
    end

    test "does not return gifts from another account" do
      {account1, user1} = setup_account()
      {account2, user2} = setup_account()
      contact1 = insert(:contact, account: account1)
      contact2 = insert(:contact, account: account2)
      insert(:gift, account: account1, contact: contact1, creator: user1)
      insert(:gift, account: account2, contact: contact2, creator: user2)

      assert [gift] = Gifts.list_gifts(account1.id, contact1.id)
      assert gift.account_id == account1.id
    end
  end

  describe "get_gift!/2" do
    test "returns a gift by id scoped to account" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      gift = insert(:gift, account: account, contact: contact, creator: user)

      fetched = Gifts.get_gift!(account.id, gift.id)
      assert fetched.id == gift.id
    end

    test "raises for gift in another account" do
      {account1, user1} = setup_account()
      {account2, _user2} = setup_account()
      contact = insert(:contact, account: account1)
      gift = insert(:gift, account: account1, contact: contact, creator: user1)

      assert_raise Ecto.NoResultsError, fn ->
        Gifts.get_gift!(account2.id, gift.id)
      end
    end
  end

  describe "create_gift/3" do
    test "creates a gift with valid attrs" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "name" => "Birthday cake",
        "direction" => "given",
        "contact_id" => contact.id,
        "status" => "idea",
        "occasion" => "birthday"
      }

      assert {:ok, gift} = Gifts.create_gift(account.id, user.id, attrs)
      assert gift.name == "Birthday cake"
      assert gift.direction == "given"
      assert gift.status == "idea"
      assert gift.occasion == "birthday"
    end

    test "fails without name" do
      {account, user} = setup_account()

      attrs = %{"direction" => "given"}
      assert {:error, changeset} = Gifts.create_gift(account.id, user.id, attrs)
      assert errors_on(changeset).name
    end

    test "fails without direction" do
      {account, user} = setup_account()

      attrs = %{"name" => "Something"}
      assert {:error, changeset} = Gifts.create_gift(account.id, user.id, attrs)
      assert errors_on(changeset).direction
    end

    test "fails with invalid direction" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{"name" => "Test", "direction" => "stolen", "contact_id" => contact.id}
      assert {:error, changeset} = Gifts.create_gift(account.id, user.id, attrs)
      assert errors_on(changeset).direction
    end

    test "fails with invalid status" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "name" => "Test",
        "direction" => "given",
        "status" => "lost",
        "contact_id" => contact.id
      }

      assert {:error, changeset} = Gifts.create_gift(account.id, user.id, attrs)
      assert errors_on(changeset).status
    end

    test "defaults status to idea" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{"name" => "Flowers", "direction" => "given", "contact_id" => contact.id}
      assert {:ok, gift} = Gifts.create_gift(account.id, user.id, attrs)
      assert gift.status == "idea"
    end
  end

  describe "update_gift/2" do
    test "updates gift attributes" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      gift = insert(:gift, account: account, contact: contact, creator: user)

      assert {:ok, updated} =
               Gifts.update_gift(gift, %{name: "Updated gift", status: "purchased"})

      assert updated.name == "Updated gift"
      assert updated.status == "purchased"
    end
  end

  describe "delete_gift/1" do
    test "deletes the gift" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      gift = insert(:gift, account: account, contact: contact, creator: user)

      assert {:ok, _} = Gifts.delete_gift(gift)
      assert Gifts.list_gifts(account.id, contact.id) == []
    end
  end

  describe "list_gift_ideas/1" do
    test "returns only gifts with status idea" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      insert(:gift, account: account, contact: contact, creator: user, status: "idea")
      insert(:gift, account: account, contact: contact, creator: user, status: "given")

      assert [idea] = Gifts.list_gift_ideas(account.id)
      assert idea.status == "idea"
    end

    test "returns ideas from all contacts in the account" do
      {account, user} = setup_account()
      contact1 = insert(:contact, account: account)
      contact2 = insert(:contact, account: account)
      insert(:gift, account: account, contact: contact1, creator: user, status: "idea")
      insert(:gift, account: account, contact: contact2, creator: user, status: "idea")

      assert length(Gifts.list_gift_ideas(account.id)) == 2
    end
  end
end
