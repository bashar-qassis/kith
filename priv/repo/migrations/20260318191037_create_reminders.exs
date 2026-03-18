defmodule Kith.Repo.Migrations.CreateReminders do
  use Ecto.Migration

  def change do
    # ── reminders ──────────────────────────────────────────────────────
    create table(:reminders) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :reminder_type, :string, null: false
      add :title, :string
      add :description, :text
      add :initial_date, :date, null: false
      add :frequency_type, :string
      add :frequency_number, :integer
      add :enqueued_oban_job_ids, :map, null: false, default: "[]"
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create constraint(:reminders, :reminders_reminder_type_values,
             check: "reminder_type IN ('birthday', 'stay_in_touch', 'one_time', 'recurring')"
           )

    create constraint(:reminders, :reminders_frequency_type_values,
             check: "frequency_type IN ('weekly', 'monthly', 'yearly') OR frequency_type IS NULL"
           )

    create index(:reminders, [:contact_id])
    create index(:reminders, [:account_id])
    create index(:reminders, [:reminder_type])

    # ── reminder_rules ─────────────────────────────────────────────────
    create table(:reminder_rules) do
      add :reminder_id, references(:reminders, on_delete: :delete_all), null: false
      add :number_of_days_before, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:reminder_rules, [:reminder_id])

    # ── reminder_instances ─────────────────────────────────────────────
    create table(:reminder_instances) do
      add :reminder_id, references(:reminders, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :scheduled_at, :utc_datetime, null: false
      add :fired_at, :utc_datetime
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create constraint(:reminder_instances, :reminder_instances_status_values,
             check: "status IN ('pending', 'resolved', 'dismissed')"
           )

    create index(:reminder_instances, [:reminder_id])
    create index(:reminder_instances, [:account_id, :status])
    create index(:reminder_instances, [:scheduled_at])
  end
end
