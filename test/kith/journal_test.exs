defmodule Kith.JournalTest do
  use Kith.DataCase, async: false

  import Kith.Factory

  alias Kith.Journal

  describe "list_entries/2" do
    test "returns entries for the account" do
      {account, user} = setup_account()
      entry = insert(:journal_entry, account: account, author: user)

      assert [returned] = Journal.list_entries(account.id)
      assert returned.id == entry.id
    end

    test "does not return entries from another account" do
      {account1, user1} = setup_account()
      {account2, user2} = setup_account()
      insert(:journal_entry, account: account1, author: user1)
      insert(:journal_entry, account: account2, author: user2)

      assert [entry] = Journal.list_entries(account1.id)
      assert entry.account_id == account1.id
    end

    test "orders by occurred_at descending" do
      {account, user} = setup_account()
      now = DateTime.utc_now(:second)
      earlier = DateTime.add(now, -3600, :second)

      insert(:journal_entry, account: account, author: user, occurred_at: earlier, title: "Earlier")
      insert(:journal_entry, account: account, author: user, occurred_at: now, title: "Later")

      entries = Journal.list_entries(account.id)
      assert [%{title: "Later"}, %{title: "Earlier"}] = entries
    end
  end

  describe "list_entries/2 with author_id (privacy filtering)" do
    test "without author_id returns all entries" do
      {account, user} = setup_account()
      user2 = insert(:user, account: account, role: "editor")

      insert(:journal_entry, account: account, author: user, is_private: true)
      insert(:journal_entry, account: account, author: user2, is_private: true)
      insert(:journal_entry, account: account, author: user, is_private: false)

      # Without author_id filtering, all are returned
      assert length(Journal.list_entries(account.id)) == 3
    end

    test "with author_id returns own private entries and all public entries" do
      {account, user} = setup_account()
      user2 = insert(:user, account: account, role: "editor")

      insert(:journal_entry, account: account, author: user, is_private: true, title: "My private")
      insert(:journal_entry, account: account, author: user2, is_private: true, title: "Their private")
      insert(:journal_entry, account: account, author: user2, is_private: false, title: "Their public")

      entries = Journal.list_entries(account.id, author_id: user.id)
      titles = Enum.map(entries, & &1.title)

      assert "My private" in titles
      assert "Their public" in titles
      refute "Their private" in titles
      assert length(entries) == 2
    end
  end

  describe "list_entries/2 with mood filter" do
    test "filters by mood" do
      {account, user} = setup_account()
      insert(:journal_entry, account: account, author: user, mood: "great")
      insert(:journal_entry, account: account, author: user, mood: "awful")

      assert [entry] = Journal.list_entries(account.id, mood: "great")
      assert entry.mood == "great"
    end
  end

  describe "get_entry!/2" do
    test "returns an entry by id scoped to account" do
      {account, user} = setup_account()
      entry = insert(:journal_entry, account: account, author: user)

      fetched = Journal.get_entry!(account.id, entry.id)
      assert fetched.id == entry.id
    end

    test "raises for entry in another account" do
      {account1, user1} = setup_account()
      {account2, _user2} = setup_account()
      entry = insert(:journal_entry, account: account1, author: user1)

      assert_raise Ecto.NoResultsError, fn ->
        Journal.get_entry!(account2.id, entry.id)
      end
    end
  end

  describe "get_entry/2" do
    test "returns nil when not found" do
      {account, _user} = setup_account()
      assert Journal.get_entry(account.id, 999_999) == nil
    end
  end

  describe "create_entry/3" do
    test "creates an entry with valid attrs" do
      {account, user} = setup_account()

      attrs = %{
        "title" => "A great day",
        "content" => "<p>Went for a walk.</p>",
        "occurred_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601(),
        "mood" => "great"
      }

      assert {:ok, entry} = Journal.create_entry(account.id, user.id, attrs)
      assert entry.title == "A great day"
      assert entry.content == "<p>Went for a walk.</p>"
      assert entry.mood == "great"
      assert entry.account_id == account.id
      assert entry.author_id == user.id
    end

    test "fails without content" do
      {account, user} = setup_account()

      attrs = %{
        "title" => "Test",
        "occurred_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }

      assert {:error, changeset} = Journal.create_entry(account.id, user.id, attrs)
      assert errors_on(changeset).content
    end

    test "fails without occurred_at" do
      {account, user} = setup_account()

      attrs = %{"content" => "<p>Test</p>"}
      assert {:error, changeset} = Journal.create_entry(account.id, user.id, attrs)
      assert errors_on(changeset).occurred_at
    end

    test "fails with invalid mood" do
      {account, user} = setup_account()

      attrs = %{
        "content" => "<p>Test</p>",
        "occurred_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601(),
        "mood" => "ecstatic"
      }

      assert {:error, changeset} = Journal.create_entry(account.id, user.id, attrs)
      assert errors_on(changeset).mood
    end

    test "allows nil mood" do
      {account, user} = setup_account()

      attrs = %{
        "content" => "<p>No mood today</p>",
        "occurred_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }

      assert {:ok, entry} = Journal.create_entry(account.id, user.id, attrs)
      assert entry.mood == nil
    end

    test "defaults is_private to true" do
      {account, user} = setup_account()

      attrs = %{
        "content" => "<p>Private by default</p>",
        "occurred_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }

      assert {:ok, entry} = Journal.create_entry(account.id, user.id, attrs)
      assert entry.is_private == true
    end
  end

  describe "update_entry/2" do
    test "updates entry attributes" do
      {account, user} = setup_account()
      entry = insert(:journal_entry, account: account, author: user)

      assert {:ok, updated} = Journal.update_entry(entry, %{title: "Updated title", mood: "neutral"})
      assert updated.title == "Updated title"
      assert updated.mood == "neutral"
    end

    test "can make entry public" do
      {account, user} = setup_account()
      entry = insert(:journal_entry, account: account, author: user, is_private: true)

      assert {:ok, updated} = Journal.update_entry(entry, %{is_private: false})
      assert updated.is_private == false
    end
  end

  describe "delete_entry/1" do
    test "deletes the entry" do
      {account, user} = setup_account()
      entry = insert(:journal_entry, account: account, author: user)

      assert {:ok, _} = Journal.delete_entry(entry)
      assert Journal.list_entries(account.id) == []
    end
  end

  describe "entries_by_mood/2" do
    test "returns entries with matching mood" do
      {account, user} = setup_account()
      insert(:journal_entry, account: account, author: user, mood: "good")
      insert(:journal_entry, account: account, author: user, mood: "bad")
      insert(:journal_entry, account: account, author: user, mood: "good")

      entries = Journal.entries_by_mood(account.id, "good")
      assert length(entries) == 2
      assert Enum.all?(entries, &(&1.mood == "good"))
    end

    test "returns empty list when no entries match" do
      {account, user} = setup_account()
      insert(:journal_entry, account: account, author: user, mood: "good")

      assert Journal.entries_by_mood(account.id, "awful") == []
    end
  end
end
