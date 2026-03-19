defmodule Kith.Repo.Migrations.Phase06RemindersNotifications do
  use Ecto.Migration

  def change do
    # ── reminders: align columns with Phase 06 plan ──────────────────────
    alter table(:reminders) do
      # Rename existing columns
      remove :reminder_type
      remove :description
      remove :initial_date
      remove :frequency_type
      remove :frequency_number
      remove :enqueued_oban_job_ids

      # Add columns per Phase 06 spec
      add :type, :string, null: false, default: "one_time"
      add :frequency, :string
      add :next_reminder_date, :date, null: false, default: fragment("CURRENT_DATE")
      add :creator_id, references(:users, on_delete: :nothing), null: false
      add :enqueued_oban_job_ids, :jsonb, null: false, default: "[]"
    end

    # Drop old constraints
    drop_if_exists constraint(:reminders, :reminders_reminder_type_values)
    drop_if_exists constraint(:reminders, :reminders_frequency_type_values)

    # Drop old indexes
    drop_if_exists index(:reminders, [:reminder_type])

    # New indexes per plan
    create index(:reminders, [:contact_id],
             where: "active = true",
             name: :reminders_contact_active_idx
           )

    create index(:reminders, [:account_id, :next_reminder_date],
             where: "active = true",
             name: :reminders_account_next_date_idx
           )

    create unique_index(:reminders, [:contact_id],
             where: "type = 'birthday'",
             name: :reminders_birthday_unique_idx
           )

    # ── reminder_rules: restructure as account-level config ──────────────
    # Drop old table and recreate (was per-reminder, now per-account)
    drop table(:reminder_rules)

    create table(:reminder_rules) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :days_before, :integer, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:reminder_rules, [:account_id, :days_before])

    # ── reminder_instances: add missing columns ──────────────────────────
    # Drop old status constraint to add 'failed'
    drop_if_exists constraint(:reminder_instances, :reminder_instances_status_values)

    alter table(:reminder_instances) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :resolved_at, :utc_datetime
      # Rename scheduled_at to scheduled_for per plan
      remove :scheduled_at
      add :scheduled_for, :utc_datetime, null: false
    end

    # Re-create status constraint with 'failed'
    create constraint(:reminder_instances, :reminder_instances_status_values,
             check: "status IN ('pending', 'resolved', 'dismissed', 'failed')"
           )

    create index(:reminder_instances, [:reminder_id],
             where: "status = 'pending'",
             name: :reminder_instances_pending_idx
           )

    create index(:reminder_instances, [:contact_id])
  end
end
