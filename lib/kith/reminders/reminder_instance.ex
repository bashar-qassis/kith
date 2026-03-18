defmodule Kith.Reminders.ReminderInstance do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reminder_instances" do
    field :scheduled_at, :utc_datetime
    field :fired_at, :utc_datetime
    field :status, :string, default: "pending"

    belongs_to :reminder, Kith.Reminders.Reminder
    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(reminder_instance, attrs) do
    reminder_instance
    |> cast(attrs, [:scheduled_at, :fired_at, :status, :reminder_id, :account_id])
    |> validate_required([:scheduled_at])
    |> validate_inclusion(:status, ["pending", "resolved", "dismissed"])
    |> foreign_key_constraint(:reminder_id)
    |> foreign_key_constraint(:account_id)
  end
end
