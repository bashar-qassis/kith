defmodule Kith.RemindersSnoozeTest do
  use Kith.DataCase, async: true

  alias Kith.Reminders
  alias Kith.Reminders.ReminderInstance

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures
  import Kith.RemindersFixtures

  setup do
    seed_reference_data!()
    user = user_fixture()
    account_id = user.account_id
    contact = contact_fixture(account_id)
    seed_reminder_rules!(account_id)
    %{user: user, account_id: account_id, contact: contact}
  end

  describe "snooze_instance/2 with valid duration" do
    test "snoozes a pending instance for fifteen_minutes", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)

      assert {:ok, snoozed} = Reminders.snooze_instance(i, "fifteen_minutes")
      assert snoozed.status == "snoozed"
      assert snoozed.snoozed_until != nil
      assert snoozed.snooze_count == 1
    end

    test "snoozes a pending instance for one_hour", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)

      assert {:ok, snoozed} = Reminders.snooze_instance(i, "one_hour")
      assert snoozed.status == "snoozed"
      assert snoozed.snoozed_until != nil

      # Verify snoozed_until is approximately 60 minutes from now
      diff = DateTime.diff(snoozed.snoozed_until, DateTime.utc_now(:second), :minute)
      assert diff >= 59 and diff <= 61
    end

    test "snoozes a pending instance for one_day", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)

      assert {:ok, snoozed} = Reminders.snooze_instance(i, "one_day")
      assert snoozed.status == "snoozed"

      # Verify snoozed_until is approximately 24 hours from now
      diff = DateTime.diff(snoozed.snoozed_until, DateTime.utc_now(:second), :minute)
      assert diff >= 1439 and diff <= 1441
    end

    test "snoozes a pending instance for three_days", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)

      assert {:ok, snoozed} = Reminders.snooze_instance(i, "three_days")
      assert snoozed.status == "snoozed"

      # Verify snoozed_until is approximately 3 days from now
      diff = DateTime.diff(snoozed.snoozed_until, DateTime.utc_now(:second), :minute)
      assert diff >= 4319 and diff <= 4321
    end

    test "increments snooze_count on each snooze", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)

      # First snooze
      assert {:ok, snoozed} = Reminders.snooze_instance(i, "fifteen_minutes")
      assert snoozed.snooze_count == 1

      # Reset to pending to snooze again
      snoozed
      |> Ecto.Changeset.change(status: "pending")
      |> Repo.update!()

      reloaded = Repo.get!(ReminderInstance, snoozed.id)

      assert {:ok, snoozed_again} = Reminders.snooze_instance(reloaded, "one_hour")
      assert snoozed_again.snooze_count == 2
    end
  end

  describe "snooze_instance/2 fails on non-pending instance" do
    test "returns error for resolved instance", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)
      {:ok, resolved} = Reminders.resolve_instance(i)

      assert {:error, :invalid_status} = Reminders.snooze_instance(resolved, "one_hour")
    end

    test "returns error for dismissed instance", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)
      {:ok, dismissed} = Reminders.dismiss_instance(i)

      assert {:error, :invalid_status} = Reminders.snooze_instance(dismissed, "fifteen_minutes")
    end

    test "returns error for failed instance", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)

      failed =
        i
        |> ReminderInstance.fail_changeset()
        |> Repo.update!()

      assert {:error, :invalid_status} = Reminders.snooze_instance(failed, "one_day")
    end

    test "returns error for already snoozed instance", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)
      {:ok, snoozed} = Reminders.snooze_instance(i, "fifteen_minutes")

      assert {:error, :invalid_status} = Reminders.snooze_instance(snoozed, "one_hour")
    end
  end

  describe "ReminderInstance.snooze_durations/0" do
    test "returns all valid snooze duration keys" do
      durations = ReminderInstance.snooze_durations()

      assert "fifteen_minutes" in durations
      assert "one_hour" in durations
      assert "one_day" in durations
      assert "three_days" in durations
      assert length(durations) == 4
    end
  end

  describe "ReminderInstance.snooze_changeset/2" do
    test "sets snoozed_until correctly for each duration", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)

      cs = ReminderInstance.snooze_changeset(i, "fifteen_minutes")
      assert cs.changes.status == "snoozed"
      assert cs.changes.snoozed_until != nil
      assert cs.changes.snooze_count == 1
    end

    test "raises for invalid duration key", %{
      account_id: account_id,
      contact: contact,
      user: user
    } do
      r = reminder_fixture(account_id, contact.id, user.id)
      i = reminder_instance_fixture(r)

      assert_raise KeyError, fn ->
        ReminderInstance.snooze_changeset(i, "two_weeks")
      end
    end
  end
end
