defmodule Kith.Reminders.ReminderInstance do
  @moduledoc """
  A fired instance of a reminder. Created by `ReminderNotificationWorker` when
  a notification is sent. Tracks the lifecycle from pending → resolved/dismissed/failed.

  Uses `fired_at` (Decision A) for the timestamp when the notification was sent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending resolved dismissed failed)

  schema "reminder_instances" do
    field :status, :string, default: "pending"
    field :scheduled_for, :utc_datetime
    field :fired_at, :utc_datetime
    field :resolved_at, :utc_datetime

    belongs_to :reminder, Kith.Reminders.Reminder
    belongs_to :account, Kith.Accounts.Account
    belongs_to :contact, Kith.Contacts.Contact

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def create_changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :status,
      :scheduled_for,
      :fired_at,
      :reminder_id,
      :account_id,
      :contact_id
    ])
    |> validate_required([:scheduled_for, :reminder_id, :account_id, :contact_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:reminder_id)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:contact_id)
  end

  def resolve_changeset(instance) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(instance, status: "resolved", resolved_at: now)
  end

  def dismiss_changeset(instance) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(instance, status: "dismissed", resolved_at: now)
  end

  def fail_changeset(instance) do
    change(instance, status: "failed")
  end
end
