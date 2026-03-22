defmodule Kith.AuditLogsTest do
  use Kith.DataCase, async: true

  alias Kith.AuditLogs

  import Kith.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user, account_id: user.account_id}
  end

  describe "log_event/4" do
    test "enqueues audit log via Oban worker", %{user: user, account_id: account_id} do
      assert {:ok, _job} =
               AuditLogs.log_event(account_id, user, :contact_created,
                 contact_id: 1,
                 contact_name: "Jane Doe"
               )

      {entries, _meta} = AuditLogs.list_audit_logs(account_id)
      assert length(entries) == 1
      entry = hd(entries)
      assert entry.event == "contact_created"
      assert entry.user_name == user.display_name || user.email
      assert entry.contact_name == "Jane Doe"
      assert entry.contact_id == 1
    end

    test "accepts atom events", %{user: user, account_id: account_id} do
      assert {:ok, _job} = AuditLogs.log_event(account_id, user, :contact_updated)
      {entries, _meta} = AuditLogs.list_audit_logs(account_id)
      assert hd(entries).event == "contact_updated"
    end

    test "accepts string events", %{user: user, account_id: account_id} do
      assert {:ok, _job} = AuditLogs.log_event(account_id, user, "contact_deleted")
      {entries, _meta} = AuditLogs.list_audit_logs(account_id)
      assert hd(entries).event == "contact_deleted"
    end

    test "raises on unknown event", %{user: user, account_id: account_id} do
      assert_raise ArgumentError, ~r/unknown audit event/, fn ->
        AuditLogs.log_event(account_id, user, :unknown_event)
      end
    end

    test "captures user_name from display_name", %{account_id: account_id} do
      user = %{id: 1, display_name: "Alice Smith", email: "alice@example.com"}
      {:ok, _} = AuditLogs.log_event(account_id, user, :contact_created)
      {[entry], _} = AuditLogs.list_audit_logs(account_id)
      assert entry.user_name == "Alice Smith"
    end

    test "falls back to email for user_name", %{account_id: account_id} do
      user = %{id: 1, display_name: nil, email: "bob@example.com"}
      {:ok, _} = AuditLogs.log_event(account_id, user, :contact_created)
      {[entry], _} = AuditLogs.list_audit_logs(account_id)
      assert entry.user_name == "bob@example.com"
    end
  end

  describe "list_audit_logs/2" do
    test "returns cursor-paginated results", %{user: user, account_id: account_id} do
      for i <- 1..5 do
        AuditLogs.create_audit_log(account_id, %{
          user_id: user.id,
          user_name: "User",
          event: "contact_created",
          contact_name: "Contact #{i}"
        })
      end

      {entries, meta} = AuditLogs.list_audit_logs(account_id, %{"limit" => 3})
      assert length(entries) == 3
      assert meta.has_more == true
      assert meta.next_cursor != nil

      {page2, meta2} =
        AuditLogs.list_audit_logs(account_id, %{"limit" => 3, "cursor" => meta.next_cursor})

      assert length(page2) == 2
      assert meta2.has_more == false
    end

    test "filters by event_type", %{user: user, account_id: account_id} do
      AuditLogs.create_audit_log(account_id, %{
        user_id: user.id,
        user_name: "U",
        event: "contact_created"
      })

      AuditLogs.create_audit_log(account_id, %{
        user_id: user.id,
        user_name: "U",
        event: "contact_deleted"
      })

      {entries, _} = AuditLogs.list_audit_logs(account_id, %{"event_type" => "contact_created"})
      assert length(entries) == 1
      assert hd(entries).event == "contact_created"
    end

    test "filters by contact_name with ILIKE", %{user: user, account_id: account_id} do
      AuditLogs.create_audit_log(account_id, %{
        user_id: user.id,
        user_name: "U",
        event: "contact_created",
        contact_name: "Alice Johnson"
      })

      AuditLogs.create_audit_log(account_id, %{
        user_id: user.id,
        user_name: "U",
        event: "contact_created",
        contact_name: "Bob Smith"
      })

      {entries, _} = AuditLogs.list_audit_logs(account_id, %{"contact_name" => "alice"})
      assert length(entries) == 1
      assert hd(entries).contact_name == "Alice Johnson"
    end

    test "filters by date range", %{user: user, account_id: account_id} do
      AuditLogs.create_audit_log(account_id, %{
        user_id: user.id,
        user_name: "U",
        event: "contact_created"
      })

      today = Date.utc_today() |> Date.to_iso8601()

      {entries, _} =
        AuditLogs.list_audit_logs(account_id, %{"date_from" => today, "date_to" => today})

      assert length(entries) >= 1
    end

    test "always scoped to account_id", %{user: user, account_id: account_id} do
      other_user = user_fixture()

      AuditLogs.create_audit_log(account_id, %{
        user_id: user.id,
        user_name: "U",
        event: "contact_created"
      })

      AuditLogs.create_audit_log(other_user.account_id, %{
        user_id: other_user.id,
        user_name: "O",
        event: "contact_created"
      })

      {entries, _} = AuditLogs.list_audit_logs(account_id)
      assert Enum.all?(entries, fn e -> e.account_id == account_id end)
    end
  end

  describe "create_audit_log/2" do
    test "validates event inclusion", %{account_id: account_id} do
      assert {:error, changeset} =
               AuditLogs.create_audit_log(account_id, %{
                 user_id: 1,
                 user_name: "User",
                 event: "invalid_event"
               })

      assert %{event: ["is invalid"]} = errors_on(changeset)
    end
  end
end
