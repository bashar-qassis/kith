defmodule Kith.Repo.Migrations.Phase05SubEntityColumns do
  use Ecto.Migration

  def change do
    # ── author_id on notes (for private note filtering) ────────────────
    alter table(:notes) do
      add :author_id, references(:users, on_delete: :nilify_all)
    end

    create index(:notes, [:author_id])

    # ── is_cover on photos ─────────────────────────────────────────────
    alter table(:photos) do
      add :is_cover, :boolean, null: false, default: false
    end

    # Only one cover photo per contact
    create unique_index(:photos, [:contact_id],
             where: "is_cover = true",
             name: :photos_contact_id_cover_unique
           )

    # ── call_directions reference table ────────────────────────────────
    create table(:call_directions) do
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:call_directions, [:name])

    # ── call_direction_id on calls ─────────────────────────────────────
    alter table(:calls) do
      add :call_direction_id, references(:call_directions, on_delete: :nilify_all)
    end

    create index(:calls, [:call_direction_id])

    # ── timestamps on activity_contacts join table ─────────────────────
    alter table(:activity_contacts) do
      add :inserted_at, :utc_datetime
      add :updated_at, :utc_datetime
    end

    # ── timestamps on activity_emotions join table ─────────────────────
    alter table(:activity_emotions) do
      add :inserted_at, :utc_datetime
      add :updated_at, :utc_datetime
    end
  end
end
