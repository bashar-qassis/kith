defmodule Kith.Workers.ReminderSchedulerWorkerTest do
  use Kith.DataCase, async: true

  alias Kith.Workers.ReminderSchedulerWorker
  alias Kith.Reminders.Reminder

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures
  import Kith.RemindersFixtures

  setup do
    seed_reference_data!()
    user = user_fixture()
    account_id = user.account_id
    # Set account send_hour to 23 to ensure jobs are always scheduled in the future
    account = Kith.Repo.get!(Kith.Accounts.Account, account_id)
    Ecto.Changeset.change(account, send_hour: 23) |> Kith.Repo.update!()
    contact = contact_fixture(account_id)
    seed_reminder_rules!(account_id)
    %{user: user, account_id: account_id, contact: contact}
  end

  describe "perform/1" do
    test "enqueues jobs for due reminders", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      # Create a reminder due today
      r =
        reminder_fixture(account_id, contact.id, user.id, %{
          next_reminder_date: Date.utc_today()
        })

      assert r.enqueued_oban_job_ids == []

      # Run the scheduler
      assert :ok = ReminderSchedulerWorker.perform(%Oban.Job{args: %{}})

      # Check that job IDs were stored
      updated = Repo.get!(Reminder, r.id)
      assert length(updated.enqueued_oban_job_ids) > 0
    end

    test "skips reminders with already enqueued jobs", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r =
        reminder_fixture(account_id, contact.id, user.id, %{
          next_reminder_date: Date.utc_today()
        })

      # Manually set job IDs to simulate already-enqueued
      r |> Reminder.job_ids_changeset([999]) |> Repo.update!()

      assert :ok = ReminderSchedulerWorker.perform(%Oban.Job{args: %{}})

      # Should not have changed
      updated = Repo.get!(Reminder, r.id)
      assert updated.enqueued_oban_job_ids == [999]
    end

    test "skips stay-in-touch with pending instance", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = stay_in_touch_reminder_fixture(account_id, contact.id, user.id)
      r |> Ecto.Changeset.change(next_reminder_date: Date.utc_today()) |> Repo.update!()
      _i = reminder_instance_fixture(r)

      assert :ok = ReminderSchedulerWorker.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(Reminder, r.id)
      assert updated.enqueued_oban_job_ids == []
    end

    test "skips reminders due in the far future", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r =
        reminder_fixture(account_id, contact.id, user.id, %{
          next_reminder_date: Date.add(Date.utc_today(), 30)
        })

      assert :ok = ReminderSchedulerWorker.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(Reminder, r.id)
      assert updated.enqueued_oban_job_ids == []
    end
  end
end
