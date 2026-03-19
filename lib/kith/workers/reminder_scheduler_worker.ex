defmodule Kith.Workers.ReminderSchedulerWorker do
  @moduledoc """
  Nightly cron job (2 AM UTC) that scans for due reminders and enqueues
  `ReminderNotificationWorker` jobs.

  Algorithm:
  - For each account, load timezone/send_hour and active ReminderRules
  - For each active reminder where next_reminder_date is within next 24 hours:
    - Skip if already enqueued (enqueued_oban_job_ids not empty)
    - Skip stay-in-touch with a pending ReminderInstance
    - Compute UTC scheduled_at from account timezone + send_hour
    - Enqueue on-day job (all types) + pre-notification jobs (birthday/one_time only)
    - Store job IDs in enqueued_oban_job_ids

  Resilient to individual account/reminder failures — logs errors per-reminder
  and continues processing.
  """

  use Oban.Worker, queue: :reminders

  require Logger

  alias Kith.Repo
  alias Kith.Reminders
  alias Kith.Reminders.Reminder

  import Ecto.Query

  @impl Oban.Worker
  def perform(_job) do
    accounts = Repo.all(Kith.Accounts.Account)

    Enum.each(accounts, fn account ->
      try do
        process_account(account)
      rescue
        e ->
          Logger.error(
            "ReminderSchedulerWorker failed for account #{account.id}: #{Exception.message(e)}"
          )
      end
    end)

    :ok
  end

  defp process_account(account) do
    tomorrow = Date.add(Date.utc_today(), 1)

    reminders =
      from(r in Reminder,
        where: r.account_id == ^account.id,
        where: r.active == true,
        where: r.next_reminder_date <= ^tomorrow
      )
      |> Repo.all()

    Enum.each(reminders, fn reminder ->
      try do
        process_reminder(reminder, account)
      rescue
        e ->
          Logger.error(
            "ReminderSchedulerWorker failed for reminder #{reminder.id}: #{Exception.message(e)}"
          )
      end
    end)
  end

  defp process_reminder(reminder, account) do
    # Skip if already enqueued
    if reminder.enqueued_oban_job_ids != [] do
      :skip
    else
      # Skip stay-in-touch with pending instance
      if reminder.type == "stay_in_touch" and Reminders.has_pending_instance?(reminder.id) do
        :skip
      else
        {:ok, job_ids} = Reminders.enqueue_jobs_for_reminder(reminder, account)

        reminder
        |> Reminder.job_ids_changeset(job_ids)
        |> Repo.update!()
      end
    end
  end
end
