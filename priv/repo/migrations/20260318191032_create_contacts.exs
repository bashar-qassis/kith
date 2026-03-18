defmodule Kith.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "DROP EXTENSION IF EXISTS pg_trgm"

    create table(:contacts) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :first_name, :string, null: false
      add :last_name, :string
      add :display_name, :string
      add :nickname, :string
      add :gender_id, references(:genders, on_delete: :nilify_all)
      add :currency_id, references(:currencies, on_delete: :nilify_all)
      add :birthdate, :date
      add :description, :text
      add :avatar, :string
      add :occupation, :string
      add :company, :string
      add :favorite, :boolean, null: false, default: false
      add :is_archived, :boolean, null: false, default: false
      add :deceased, :boolean, null: false, default: false
      add :deceased_at, :date
      add :last_talked_to, :utc_datetime
      add :deleted_at, :utc_datetime

      # Immich integration
      add :immich_person_id, :string
      add :immich_person_url, :string
      add :immich_status, :string, null: false, default: "unlinked"
      add :immich_last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # CHECK constraint on immich_status
    create constraint(:contacts, :contacts_immich_status_values,
             check: "immich_status IN ('unlinked', 'needs_review', 'linked')"
           )

    # Partial indexes for soft-delete
    create index(:contacts, [:account_id],
             where: "deleted_at IS NULL",
             name: :contacts_active_idx
           )

    create index(:contacts, [:account_id, :deleted_at],
             where: "deleted_at IS NOT NULL",
             name: :contacts_trash_idx
           )

    # Archive queries
    create index(:contacts, [:account_id, :is_archived],
             where: "deleted_at IS NULL",
             name: :contacts_archive_idx
           )

    # Favorites
    create index(:contacts, [:account_id, :favorite],
             where: "deleted_at IS NULL",
             name: :contacts_favorite_idx
           )

    # Sorted listing
    create index(:contacts, [:account_id, :last_name, :first_name],
             where: "deleted_at IS NULL",
             name: :contacts_name_sort_idx
           )

    # Gender FK index
    create index(:contacts, [:gender_id])

    # Trigram index for fuzzy search on display_name
    execute(
      "CREATE INDEX contacts_display_name_trgm_idx ON contacts USING gin (display_name gin_trgm_ops)",
      "DROP INDEX IF EXISTS contacts_display_name_trgm_idx"
    )

    # ── Add FK constraint on users.me_contact_id → contacts ────────────
    alter table(:users) do
      modify :me_contact_id, references(:contacts, on_delete: :nilify_all),
        from: {:bigint, null: true}
    end
  end
end
