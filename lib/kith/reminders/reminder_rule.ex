defmodule Kith.Reminders.ReminderRule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reminder_rules" do
    field :number_of_days_before, :integer

    belongs_to :reminder, Kith.Reminders.Reminder

    timestamps(type: :utc_datetime)
  end

  def changeset(reminder_rule, attrs) do
    reminder_rule
    |> cast(attrs, [:number_of_days_before, :reminder_id])
    |> validate_required([:number_of_days_before])
    |> foreign_key_constraint(:reminder_id)
  end
end
