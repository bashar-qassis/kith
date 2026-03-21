defmodule Kith.Repo.Migrations.AddSnoozeToReminderInstances do
  use Ecto.Migration

  def change do
    alter table(:reminder_instances) do
      add :snoozed_until, :utc_datetime
      add :snooze_count, :integer, default: 0, null: false
    end

    # Update the status CHECK constraint to include "snoozed"
    execute(
      "ALTER TABLE reminder_instances DROP CONSTRAINT IF EXISTS reminder_instances_status_values",
      "ALTER TABLE reminder_instances ADD CONSTRAINT reminder_instances_status_values CHECK (status IN ('pending', 'resolved', 'dismissed', 'failed'))"
    )

    execute(
      "ALTER TABLE reminder_instances ADD CONSTRAINT reminder_instances_status_values CHECK (status IN ('pending', 'resolved', 'dismissed', 'failed', 'snoozed'))",
      "ALTER TABLE reminder_instances DROP CONSTRAINT IF EXISTS reminder_instances_status_values"
    )
  end
end
