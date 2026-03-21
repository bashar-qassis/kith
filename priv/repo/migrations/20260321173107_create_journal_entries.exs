defmodule Kith.Repo.Migrations.CreateJournalEntries do
  use Ecto.Migration

  def change do
    create table(:journal_entries) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all), null: false
      add :title, :string
      add :content, :text, null: false
      add :occurred_at, :utc_datetime, null: false
      add :mood, :string
      add :is_private, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:journal_entries, [:account_id, :occurred_at])
    create index(:journal_entries, [:author_id])
  end
end
