defmodule Kith.ConversationsTest do
  use Kith.DataCase, async: true

  import Kith.Factory

  alias Kith.Conversations

  describe "list_conversations/2" do
    test "returns conversations for the contact scoped to account" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      assert [returned] = Conversations.list_conversations(account.id, contact.id)
      assert returned.id == conv.id
    end

    test "does not return conversations from another contact" do
      {account, user} = setup_account()
      contact1 = insert(:contact, account: account)
      contact2 = insert(:contact, account: account)
      insert(:conversation, account: account, contact: contact1, creator: user)
      insert(:conversation, account: account, contact: contact2, creator: user)

      assert [conv] = Conversations.list_conversations(account.id, contact1.id)
      assert conv.contact_id == contact1.id
    end

    test "does not return conversations from another account" do
      {account1, user1} = setup_account()
      {account2, user2} = setup_account()
      contact1 = insert(:contact, account: account1)
      contact2 = insert(:contact, account: account2)
      insert(:conversation, account: account1, contact: contact1, creator: user1)
      insert(:conversation, account: account2, contact: contact2, creator: user2)

      assert [conv] = Conversations.list_conversations(account1.id, contact1.id)
      assert conv.account_id == account1.id
    end

    test "preloads messages" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)
      insert(:message, conversation: conv, account: account)

      assert [returned] = Conversations.list_conversations(account.id, contact.id)
      assert length(returned.messages) == 1
    end
  end

  describe "get_conversation!/2" do
    test "returns a conversation by id scoped to account" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      fetched = Conversations.get_conversation!(account.id, conv.id)
      assert fetched.id == conv.id
    end

    test "raises for conversation in another account" do
      {account1, user1} = setup_account()
      {account2, _user2} = setup_account()
      contact = insert(:contact, account: account1)
      conv = insert(:conversation, account: account1, contact: contact, creator: user1)

      assert_raise Ecto.NoResultsError, fn ->
        Conversations.get_conversation!(account2.id, conv.id)
      end
    end

    test "preloads messages" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)
      insert(:message, conversation: conv, account: account)

      fetched = Conversations.get_conversation!(account.id, conv.id)
      assert length(fetched.messages) == 1
    end
  end

  describe "get_conversation/2" do
    test "returns nil when not found" do
      {account, _user} = setup_account()
      assert Conversations.get_conversation(account.id, 999_999) == nil
    end
  end

  describe "create_conversation/3" do
    test "creates a conversation with valid attrs" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "subject" => "Lunch plans",
        "platform" => "whatsapp",
        "contact_id" => contact.id
      }

      assert {:ok, conv} = Conversations.create_conversation(account.id, user.id, attrs)
      assert conv.subject == "Lunch plans"
      assert conv.platform == "whatsapp"
      assert conv.status == "active"
      assert conv.account_id == account.id
      assert conv.creator_id == user.id
    end

    test "rejects invalid platform" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "subject" => "Test",
        "platform" => "carrier_pigeon",
        "contact_id" => contact.id
      }

      assert {:error, changeset} = Conversations.create_conversation(account.id, user.id, attrs)
      assert errors_on(changeset).platform
    end

    test "defaults platform to other" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{"subject" => "Test", "contact_id" => contact.id}
      assert {:ok, conv} = Conversations.create_conversation(account.id, user.id, attrs)
      assert conv.platform == "other"
    end

    test "defaults status to active" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{"subject" => "Test", "contact_id" => contact.id}
      assert {:ok, conv} = Conversations.create_conversation(account.id, user.id, attrs)
      assert conv.status == "active"
    end
  end

  describe "update_conversation/2" do
    test "updates conversation attributes" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      assert {:ok, updated} = Conversations.update_conversation(conv, %{subject: "Updated subject", status: "archived"})
      assert updated.subject == "Updated subject"
      assert updated.status == "archived"
    end

    test "rejects invalid status" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      assert {:error, changeset} = Conversations.update_conversation(conv, %{status: "deleted"})
      assert errors_on(changeset).status
    end
  end

  describe "delete_conversation/1" do
    test "deletes the conversation" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      assert {:ok, _} = Conversations.delete_conversation(conv)
      assert Conversations.list_conversations(account.id, contact.id) == []
    end
  end

  describe "add_message/2" do
    test "adds a message to a conversation" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      attrs = %{
        "body" => "Hello there!",
        "direction" => "sent",
        "sent_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }

      assert {:ok, message} = Conversations.add_message(conv, attrs)
      assert message.body == "Hello there!"
      assert message.direction == "sent"
      assert message.conversation_id == conv.id
    end

    test "sent message updates contact last_talked_to" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      attrs = %{
        "body" => "Hey!",
        "direction" => "sent",
        "sent_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }

      assert {:ok, _message} = Conversations.add_message(conv, attrs)

      updated_contact = Kith.Contacts.get_contact!(account.id, contact.id)
      assert updated_contact.last_talked_to != nil
    end

    test "received message does not update contact last_talked_to" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      # Ensure last_talked_to is nil initially
      assert contact.last_talked_to == nil

      attrs = %{
        "body" => "They said hi",
        "direction" => "received",
        "sent_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }

      assert {:ok, _message} = Conversations.add_message(conv, attrs)

      updated_contact = Kith.Contacts.get_contact!(account.id, contact.id)
      assert updated_contact.last_talked_to == nil
    end

    test "fails without required fields" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      assert {:error, changeset} = Conversations.add_message(conv, %{})
      assert errors_on(changeset).body
      assert errors_on(changeset).direction
      assert errors_on(changeset).sent_at
    end

    test "fails with invalid direction" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      attrs = %{
        "body" => "Test",
        "direction" => "forwarded",
        "sent_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }

      assert {:error, changeset} = Conversations.add_message(conv, attrs)
      assert errors_on(changeset).direction
    end
  end

  describe "list_messages/1" do
    test "returns messages for a conversation ordered by sent_at" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv = insert(:conversation, account: account, contact: contact, creator: user)

      now = DateTime.utc_now(:second)
      earlier = DateTime.add(now, -3600, :second)

      insert(:message, conversation: conv, account: account, sent_at: now, body: "Second")
      insert(:message, conversation: conv, account: account, sent_at: earlier, body: "First")

      messages = Conversations.list_messages(conv.id)
      assert length(messages) == 2
      assert hd(messages).body == "First"
    end

    test "does not return messages from other conversations" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      conv1 = insert(:conversation, account: account, contact: contact, creator: user)
      conv2 = insert(:conversation, account: account, contact: contact, creator: user)

      insert(:message, conversation: conv1, account: account)
      insert(:message, conversation: conv2, account: account)

      assert [_] = Conversations.list_messages(conv1.id)
    end
  end
end
