defmodule Kith.Repo.Migrations.CreateEventsAndInteractions do
  use Ecto.Migration

  def change do
    # ── life_events ────────────────────────────────────────────────────
    create table(:life_events) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :life_event_type_id, references(:life_event_types, on_delete: :delete_all), null: false
      add :occurred_on, :date, null: false
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create index(:life_events, [:contact_id])
    create index(:life_events, [:life_event_type_id])

    # ── activities ─────────────────────────────────────────────────────
    create table(:activities) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :activity_type_category_id,
          references(:activity_type_categories, on_delete: :nilify_all)

      add :title, :string, null: false
      add :description, :text
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:activities, [:account_id])
    create index(:activities, [:activity_type_category_id])

    # ── activity_contacts (pure join table) ────────────────────────────
    create table(:activity_contacts, primary_key: false) do
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
    end

    create unique_index(:activity_contacts, [:activity_id, :contact_id])

    # ── activity_emotions (pure join table) ────────────────────────────
    create table(:activity_emotions, primary_key: false) do
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :emotion_id, references(:emotions, on_delete: :delete_all), null: false
    end

    create unique_index(:activity_emotions, [:activity_id, :emotion_id])

    # ── calls ──────────────────────────────────────────────────────────
    create table(:calls) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :occurred_at, :utc_datetime, null: false
      add :duration_mins, :integer
      add :notes, :text
      add :emotion_id, references(:emotions, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:calls, [:contact_id])
    create index(:calls, [:account_id])
  end
end
