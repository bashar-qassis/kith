defmodule Kith.Workers.ReminderNotificationWorker do
  @moduledoc """
  Oban worker that processes a single reminder notification.
  Enqueued by `ReminderSchedulerWorker` with a specific `scheduled_at` time.

  Job args: `%{"reminder_id" => id, "type" => "on_day" | "pre_notification", "days_before" => integer}`

  Guards against stale data by reloading the reminder at execution time.
  Retries up to 3 times on email failure; after exhaustion, marks the
  ReminderInstance as `failed`.
  """

  use Oban.Worker,
    queue: :reminders,
    max_attempts: 3

  alias Kith.Reminders.{Reminder, ReminderInstance}
  alias Kith.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"reminder_id" => reminder_id, "type" => type, "days_before" => days_before} = args

    case Repo.get(Reminder, reminder_id) do
      nil ->
        {:discard, "reminder deleted"}

      %Reminder{active: false} ->
        {:discard, "reminder inactive"}

      reminder ->
        reminder = Repo.preload(reminder, [:contact, :account])
        process_notification(reminder, type, days_before)
    end
  end

  defp process_notification(reminder, type, days_before) do
    contact = reminder.contact

    cond do
      is_nil(contact) ->
        {:discard, "contact deleted"}

      not is_nil(contact.deleted_at) ->
        {:discard, "contact soft-deleted"}

      contact.deceased ->
        # Create instance as dismissed for deceased contacts
        create_dismissed_instance(reminder)
        :ok

      true ->
        send_notification(reminder, type, days_before)
    end
  end

  defp send_notification(reminder, type, days_before) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Create ReminderInstance
    {:ok, instance} =
      %ReminderInstance{}
      |> ReminderInstance.create_changeset(%{
        reminder_id: reminder.id,
        account_id: reminder.account_id,
        contact_id: reminder.contact_id,
        scheduled_for: now,
        fired_at: now,
        status: "pending"
      })
      |> Repo.insert()

    # Build and send email
    email = build_email(reminder, type, days_before)

    case Kith.Mailer.deliver(email) do
      {:ok, _} ->
        Kith.AuditLogs.create_audit_log(reminder.account_id, %{
          user_id: nil,
          user_name: "system",
          event: "reminder_fired",
          contact_id: reminder.contact_id,
          contact_name: reminder.contact.display_name,
          metadata: %{
            reminder_id: reminder.id,
            instance_id: instance.id,
            type: to_string(type)
          }
        })

        :ok

      {:error, reason} ->
        Kith.AuditLogs.create_audit_log(reminder.account_id, %{
          user_id: nil,
          user_name: "system",
          event: "reminder_fired",
          contact_id: reminder.contact_id,
          contact_name: reminder.contact.display_name,
          metadata: %{
            reminder_id: reminder.id,
            instance_id: instance.id,
            type: to_string(type),
            delivery_error: inspect(reason)
          }
        })

        {:error, reason}
    end
  end

  defp create_dismissed_instance(reminder) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %ReminderInstance{}
    |> ReminderInstance.create_changeset(%{
      reminder_id: reminder.id,
      account_id: reminder.account_id,
      contact_id: reminder.contact_id,
      scheduled_for: now,
      fired_at: now,
      status: "dismissed"
    })
    |> Repo.insert()
  end

  defp build_email(reminder, type, days_before) do
    contact = reminder.contact
    account = reminder.account
    name = contact.display_name || contact.first_name

    subject = email_subject(reminder.type, type, days_before, name, reminder.title)

    # Find all users in the account to notify
    users = Kith.Accounts.list_users(account.id)

    Enum.map(users, fn user ->
      Swoosh.Email.new()
      |> Swoosh.Email.to({user.email, user.email})
      |> Swoosh.Email.from({"Kith", "noreply@kith.app"})
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.text_body("#{subject}\n\nContact: #{name}")
    end)
    |> List.first()
  end

  defp email_subject("birthday", "on_day", _, name, _title), do: "#{name}'s birthday is today"

  defp email_subject("birthday", "pre_notification", 30, name, _),
    do: "#{name}'s birthday is in 30 days"

  defp email_subject("birthday", "pre_notification", 7, name, _),
    do: "#{name}'s birthday is in 7 days"

  defp email_subject("birthday", "pre_notification", days, name, _),
    do: "#{name}'s birthday is in #{days} days"

  defp email_subject("stay_in_touch", _, _, name, _title), do: "Time to reach out to #{name}"
  defp email_subject("one_time", "on_day", _, _name, title), do: "Reminder: #{title}"

  defp email_subject("one_time", "pre_notification", days, _name, title),
    do: "Reminder in #{days} days: #{title}"

  defp email_subject("recurring", _, _, _name, title), do: "Reminder: #{title}"
  defp email_subject(_, _, _, _name, title), do: "Reminder: #{title || "Untitled"}"

  # Called by Oban when all retries are exhausted
  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
