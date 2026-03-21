defmodule Kith.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all)
      add :creator_id, references(:users, on_delete: :nilify_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :due_date, :date
      add :priority, :string, default: "medium", null: false
      add :status, :string, default: "pending", null: false
      add :completed_at, :utc_datetime
      add :is_private, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:account_id])
    create index(:tasks, [:contact_id])
    create index(:tasks, [:account_id, :status])
    create index(:tasks, [:account_id, :due_date])
  end
end
