defmodule Kith.Repo.Migrations.CreateContactSubEntities do
  use Ecto.Migration

  def change do
    # ── addresses ──────────────────────────────────────────────────────
    create table(:addresses) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :label, :string
      add :line1, :string
      add :line2, :string
      add :city, :string
      add :province, :string
      add :postal_code, :string
      add :country, :string
      add :latitude, :float
      add :longitude, :float

      timestamps(type: :utc_datetime)
    end

    create index(:addresses, [:contact_id])
    create index(:addresses, [:account_id])

    # ── contact_fields ─────────────────────────────────────────────────
    create table(:contact_fields) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :contact_field_type_id, references(:contact_field_types, on_delete: :delete_all),
        null: false

      add :value, :string, null: false
      add :label, :string

      timestamps(type: :utc_datetime)
    end

    create index(:contact_fields, [:contact_id])
    create index(:contact_fields, [:contact_field_type_id])

    # ── tags ───────────────────────────────────────────────────────────
    create table(:tags) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:account_id, :name])

    # ── contact_tags (pure join table) ─────────────────────────────────
    create table(:contact_tags, primary_key: false) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:contact_tags, [:contact_id, :tag_id])
    create index(:contact_tags, [:tag_id])

    # ── relationships ──────────────────────────────────────────────────
    create table(:relationships) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :related_contact_id, references(:contacts, on_delete: :delete_all), null: false

      add :relationship_type_id, references(:relationship_types, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:relationships, [
             :account_id,
             :contact_id,
             :related_contact_id,
             :relationship_type_id
           ])

    create index(:relationships, [:contact_id])
    create index(:relationships, [:related_contact_id])
  end
end
