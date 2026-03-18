defmodule Kith.Repo.Migrations.CreateContentSubEntities do
  use Ecto.Migration

  def change do
    # ── notes ──────────────────────────────────────────────────────────
    create table(:notes) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :favorite, :boolean, null: false, default: false
      add :is_private, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:notes, [:contact_id])
    create index(:notes, [:account_id])

    # ── documents ──────────────────────────────────────────────────────
    create table(:documents) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :file_name, :string, null: false
      add :storage_key, :string, null: false
      add :file_size, :integer, null: false
      add :content_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:documents, [:contact_id])

    # ── photos ─────────────────────────────────────────────────────────
    create table(:photos) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :file_name, :string, null: false
      add :storage_key, :string, null: false
      add :file_size, :integer, null: false
      add :content_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:photos, [:contact_id])
  end
end
