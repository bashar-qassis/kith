defmodule Kith.Workers.ContactPurgeWorkerTest do
  use Kith.DataCase, async: true

  alias Kith.Workers.ContactPurgeWorker
  alias Kith.Contacts.Contact

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup do
    seed_reference_data!()
    user = user_fixture()
    account_id = user.account_id
    %{user: user, account_id: account_id}
  end

  describe "perform/1" do
    test "purges contacts deleted over 30 days ago", %{account_id: account_id} do
      contact = contact_fixture(account_id)

      # Soft-delete and backdate to 31 days ago
      old_time =
        DateTime.utc_now() |> DateTime.add(-31 * 86_400, :second) |> DateTime.truncate(:second)

      contact
      |> Ecto.Changeset.change(deleted_at: old_time)
      |> Repo.update!()

      assert :ok = ContactPurgeWorker.perform(%Oban.Job{args: %{}})

      assert Repo.get(Contact, contact.id) == nil
    end

    test "does NOT purge contacts deleted less than 30 days ago", %{account_id: account_id} do
      contact = contact_fixture(account_id)

      recent_time =
        DateTime.utc_now() |> DateTime.add(-10 * 86_400, :second) |> DateTime.truncate(:second)

      contact
      |> Ecto.Changeset.change(deleted_at: recent_time)
      |> Repo.update!()

      assert :ok = ContactPurgeWorker.perform(%Oban.Job{args: %{}})

      assert Repo.get(Contact, contact.id) != nil
    end

    test "does NOT purge non-deleted contacts", %{account_id: account_id} do
      contact = contact_fixture(account_id)

      assert :ok = ContactPurgeWorker.perform(%Oban.Job{args: %{}})

      assert Repo.get(Contact, contact.id) != nil
    end

    test "creates audit log entry for purged contact", %{account_id: account_id} do
      contact = contact_fixture(account_id)

      old_time =
        DateTime.utc_now() |> DateTime.add(-31 * 86_400, :second) |> DateTime.truncate(:second)

      contact
      |> Ecto.Changeset.change(deleted_at: old_time)
      |> Repo.update!()

      assert :ok = ContactPurgeWorker.perform(%Oban.Job{args: %{}})

      {logs, _meta} = Kith.AuditLogs.list_audit_logs(account_id)
      assert length(logs) == 1
      assert hd(logs).event == "contact_purged"
    end
  end
end
