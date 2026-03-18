defmodule Kith.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      # Intentionally NO FK — audit entries survive user/contact deletion
      add :user_id, :integer
      add :user_name, :string, null: false
      add :contact_id, :integer
      add :contact_name, :string

      add :event, :string, null: false
      add :metadata, :map, null: false, default: %{}

      # Audit logs are append-only: inserted_at only, no updated_at
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:account_id, :inserted_at])
    create index(:audit_logs, [:account_id, :event])

    create index(:audit_logs, [:account_id, :contact_id],
             where: "contact_id IS NOT NULL",
             name: :audit_logs_account_contact_idx
           )
  end
end
