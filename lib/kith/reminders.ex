defmodule Kith.Reminders do
  @moduledoc """
  The Reminders context — manages reminders, reminder rules, and reminder instances.
  """

  import Ecto.Query, warn: false
  import Kith.Scope

  alias Kith.Repo

  alias Kith.Reminders.{
    Reminder,
    ReminderRule,
    ReminderInstance
  }

  ## Reminders

  def list_reminders(contact_id) do
    from(r in Reminder,
      where: r.contact_id == ^contact_id,
      preload: [:reminder_rules]
    )
    |> Repo.all()
  end

  def list_active_reminders(account_id) do
    Reminder
    |> scope_to_account(account_id)
    |> where([r], r.active == true)
    |> Repo.all()
  end

  def get_reminder!(account_id, id) do
    Reminder
    |> scope_to_account(account_id)
    |> Repo.get!(id)
    |> Repo.preload([:reminder_rules, :reminder_instances])
  end

  def create_reminder(%{account_id: _, id: _} = contact, attrs) do
    %Reminder{}
    |> Reminder.changeset(
      attrs
      |> Map.put(:contact_id, contact.id)
      |> Map.put(:account_id, contact.account_id)
    )
    |> Repo.insert()
  end

  def update_reminder(%Reminder{} = reminder, attrs) do
    reminder
    |> Reminder.changeset(attrs)
    |> Repo.update()
  end

  def delete_reminder(%Reminder{} = reminder) do
    Repo.delete(reminder)
  end

  def deactivate_reminder(%Reminder{} = reminder) do
    reminder
    |> Ecto.Changeset.change(%{active: false})
    |> Repo.update()
  end

  def activate_reminder(%Reminder{} = reminder) do
    reminder
    |> Ecto.Changeset.change(%{active: true})
    |> Repo.update()
  end

  ## Reminder Rules

  def create_reminder_rule(%Reminder{} = reminder, attrs) do
    %ReminderRule{}
    |> ReminderRule.changeset(Map.put(attrs, :reminder_id, reminder.id))
    |> Repo.insert()
  end

  def delete_reminder_rule(%ReminderRule{} = rule) do
    Repo.delete(rule)
  end

  ## Reminder Instances

  def list_pending_instances(account_id) do
    ReminderInstance
    |> scope_to_account(account_id)
    |> where([i], i.status == "pending")
    |> order_by([i], asc: i.scheduled_at)
    |> Repo.all()
  end

  def list_instances_for_reminder(reminder_id) do
    from(i in ReminderInstance, where: i.reminder_id == ^reminder_id)
    |> Repo.all()
  end

  def create_reminder_instance(%Reminder{} = reminder, attrs) do
    %ReminderInstance{}
    |> ReminderInstance.changeset(
      attrs
      |> Map.put(:reminder_id, reminder.id)
      |> Map.put(:account_id, reminder.account_id)
    )
    |> Repo.insert()
  end

  def fire_instance(%ReminderInstance{} = instance) do
    instance
    |> Ecto.Changeset.change(%{fired_at: DateTime.utc_now(:second), status: "resolved"})
    |> Repo.update()
  end

  def dismiss_instance(%ReminderInstance{} = instance) do
    instance
    |> Ecto.Changeset.change(%{status: "dismissed"})
    |> Repo.update()
  end
end
