defmodule Kith.Repo.Migrations.CreateImportsAndImportRecords do
  use Ecto.Migration

  def change do
    create table(:imports) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all), null: false
      add :source, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :file_name, :string
      add :file_size, :integer
      add :file_storage_key, :string
      add :api_url, :string
      add :api_key_encrypted, :binary
      add :api_options, :map
      add :summary, :map
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:imports, [:account_id])

    # Concurrent import guard: only one pending/processing import per account
    create unique_index(:imports, [:account_id],
             where: "status IN ('pending', 'processing')",
             name: :imports_one_active_per_account_idx
           )

    create table(:import_records) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :import_id, references(:imports, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :source_entity_type, :string, null: false
      add :source_entity_id, :string, null: false
      add :local_entity_type, :string, null: false
      add :local_entity_id, :bigint, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :import_records,
             [:account_id, :source, :source_entity_type, :source_entity_id],
             name: :import_records_source_unique_idx
           )

    create index(:import_records, [:import_id])
    create index(:import_records, [:local_entity_type, :local_entity_id])
  end
end
