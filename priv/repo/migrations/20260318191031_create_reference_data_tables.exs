defmodule Kith.Repo.Migrations.CreateReferenceDataTables do
  use Ecto.Migration

  def change do
    # ── currencies (global, no account_id) ─────────────────────────────
    create table(:currencies) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :symbol, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:currencies, [:code])

    # ── genders ────────────────────────────────────────────────────────
    create table(:genders) do
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # COALESCE handles NULL account_id for global defaults
    create unique_index(:genders, ["COALESCE(account_id, 0)", :name],
             name: :genders_account_id_name_index
           )

    # ── emotions ───────────────────────────────────────────────────────
    create table(:emotions) do
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:emotions, ["COALESCE(account_id, 0)", :name],
             name: :emotions_account_id_name_index
           )

    # ── activity_type_categories ───────────────────────────────────────
    create table(:activity_type_categories) do
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :name, :string, null: false
      add :icon, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:activity_type_categories, ["COALESCE(account_id, 0)", :name],
             name: :activity_type_categories_account_id_name_index
           )

    # ── life_event_types ───────────────────────────────────────────────
    create table(:life_event_types) do
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :name, :string, null: false
      add :icon, :string
      add :category, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:life_event_types, ["COALESCE(account_id, 0)", :name],
             name: :life_event_types_account_id_name_index
           )

    # ── contact_field_types ────────────────────────────────────────────
    create table(:contact_field_types) do
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :name, :string, null: false
      add :protocol, :string
      add :icon, :string
      add :vcard_label, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contact_field_types, ["COALESCE(account_id, 0)", :name],
             name: :contact_field_types_account_id_name_index
           )

    # ── relationship_types ─────────────────────────────────────────────
    create table(:relationship_types) do
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :name, :string, null: false
      add :reverse_name, :string, null: false
      add :is_bidirectional, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:relationship_types, ["COALESCE(account_id, 0)", :name],
             name: :relationship_types_account_id_name_index
           )
  end
end
