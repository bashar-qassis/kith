defmodule Kith.Repo.Migrations.CreateConversationsAndMessages do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :creator_id, references(:users, on_delete: :nilify_all), null: false
      add :subject, :string
      add :platform, :string, default: "other", null: false
      add :status, :string, default: "active", null: false
      add :is_private, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:contact_id])
    create index(:conversations, [:account_id])

    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :direction, :string, null: false
      add :sent_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:account_id, :sent_at])
  end
end
