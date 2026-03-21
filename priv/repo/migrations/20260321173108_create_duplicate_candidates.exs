defmodule Kith.Repo.Migrations.CreateDuplicateCandidates do
  use Ecto.Migration

  def change do
    create table(:duplicate_candidates) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :duplicate_contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :score, :float, null: false
      add :reasons, {:array, :string}, default: [], null: false
      add :status, :string, default: "pending", null: false
      add :detected_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:duplicate_candidates, [:account_id, :status])

    # Canonicalize: contact_id < duplicate_contact_id to prevent A-B / B-A duplicates
    create unique_index(:duplicate_candidates, [:account_id, :contact_id, :duplicate_contact_id])

    # Ensure contact_id < duplicate_contact_id
    execute(
      "ALTER TABLE duplicate_candidates ADD CONSTRAINT contact_id_ordering CHECK (contact_id < duplicate_contact_id)",
      "ALTER TABLE duplicate_candidates DROP CONSTRAINT contact_id_ordering"
    )
  end
end
