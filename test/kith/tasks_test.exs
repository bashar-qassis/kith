defmodule Kith.TasksTest do
  use Kith.DataCase, async: true

  import Kith.Factory

  alias Kith.Tasks

  describe "list_tasks/2" do
    test "returns tasks for the account" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      task = insert(:task, account: account, contact: contact, creator: user)

      assert [returned] = Tasks.list_tasks(account.id)
      assert returned.id == task.id
    end

    test "does not return tasks from another account" do
      {account1, user1} = setup_account()
      {account2, user2} = setup_account()
      contact1 = insert(:contact, account: account1)
      contact2 = insert(:contact, account: account2)
      insert(:task, account: account1, contact: contact1, creator: user1)
      insert(:task, account: account2, contact: contact2, creator: user2)

      assert [task] = Tasks.list_tasks(account1.id)
      assert task.account_id == account1.id
    end

    test "filters by contact_id" do
      {account, user} = setup_account()
      contact1 = insert(:contact, account: account)
      contact2 = insert(:contact, account: account)
      insert(:task, account: account, contact: contact1, creator: user)
      insert(:task, account: account, contact: contact2, creator: user)

      assert [task] = Tasks.list_tasks(account.id, contact_id: contact1.id)
      assert task.contact_id == contact1.id
    end

    test "filters by status" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      insert(:task, account: account, contact: contact, creator: user, status: "pending")

      insert(:task,
        account: account,
        contact: contact,
        creator: user,
        status: "completed",
        completed_at: DateTime.utc_now(:second)
      )

      assert [task] = Tasks.list_tasks(account.id, status: "pending")
      assert task.status == "pending"
    end

    test "returns all when no filters given" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      insert(:task, account: account, contact: contact, creator: user)
      insert(:task, account: account, contact: contact, creator: user)

      assert length(Tasks.list_tasks(account.id)) == 2
    end
  end

  describe "get_task!/2" do
    test "returns a task by id scoped to account" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      task = insert(:task, account: account, contact: contact, creator: user)

      fetched = Tasks.get_task!(account.id, task.id)
      assert fetched.id == task.id
    end

    test "raises for task in another account" do
      {account1, user1} = setup_account()
      {account2, _user2} = setup_account()
      contact = insert(:contact, account: account1)
      task = insert(:task, account: account1, contact: contact, creator: user1)

      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_task!(account2.id, task.id)
      end
    end
  end

  describe "create_task/3" do
    test "creates a task with valid attrs" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "title" => "Call dentist",
        "contact_id" => contact.id,
        "priority" => "high"
      }

      assert {:ok, task} = Tasks.create_task(account.id, user.id, attrs)
      assert task.title == "Call dentist"
      assert task.priority == "high"
      assert task.status == "pending"
      assert task.account_id == account.id
      assert task.creator_id == user.id
    end

    test "fails without title" do
      {account, user} = setup_account()

      assert {:error, changeset} = Tasks.create_task(account.id, user.id, %{})
      assert errors_on(changeset).title
    end

    test "fails with invalid priority" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{"title" => "Test", "contact_id" => contact.id, "priority" => "ultra"}
      assert {:error, changeset} = Tasks.create_task(account.id, user.id, attrs)
      assert errors_on(changeset).priority
    end

    test "defaults status to pending" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{"title" => "Test task", "contact_id" => contact.id}
      assert {:ok, task} = Tasks.create_task(account.id, user.id, attrs)
      assert task.status == "pending"
    end
  end

  describe "update_task/2" do
    test "updates task attributes" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      task = insert(:task, account: account, contact: contact, creator: user)

      assert {:ok, updated} = Tasks.update_task(task, %{title: "Updated title"})
      assert updated.title == "Updated title"
    end
  end

  describe "complete_task/1" do
    test "sets status to completed and completed_at" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      task = insert(:task, account: account, contact: contact, creator: user)

      assert {:ok, completed} = Tasks.complete_task(task)
      assert completed.status == "completed"
      assert completed.completed_at != nil
    end
  end

  describe "overdue_tasks/1" do
    test "returns tasks past due date" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      insert(:task,
        account: account,
        contact: contact,
        creator: user,
        due_date: Date.add(Date.utc_today(), -1)
      )

      insert(:task,
        account: account,
        contact: contact,
        creator: user,
        due_date: Date.add(Date.utc_today(), 7)
      )

      assert [overdue] = Tasks.overdue_tasks(account.id)
      assert Date.compare(overdue.due_date, Date.utc_today()) == :lt
    end

    test "excludes completed tasks" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      insert(:task,
        account: account,
        contact: contact,
        creator: user,
        due_date: Date.add(Date.utc_today(), -3),
        status: "completed",
        completed_at: DateTime.utc_now(:second)
      )

      assert Tasks.overdue_tasks(account.id) == []
    end

    test "excludes tasks with no due date" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      insert(:task,
        account: account,
        contact: contact,
        creator: user,
        due_date: nil
      )

      assert Tasks.overdue_tasks(account.id) == []
    end
  end

  describe "delete_task/1" do
    test "deletes the task" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      task = insert(:task, account: account, contact: contact, creator: user)

      assert {:ok, _} = Tasks.delete_task(task)
      assert Tasks.list_tasks(account.id) == []
    end
  end
end
