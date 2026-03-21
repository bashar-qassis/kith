defmodule Kith.Repo.Migrations.CreateDebtsAndPayments do
  use Ecto.Migration

  def change do
    create table(:debts) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :creator_id, references(:users, on_delete: :nilify_all), null: false
      add :title, :string, null: false
      add :amount, :decimal, precision: 12, scale: 2, null: false
      add :currency_id, references(:currencies, on_delete: :nilify_all)
      add :direction, :string, null: false
      add :status, :string, default: "active", null: false
      add :due_date, :date
      add :notes, :text
      add :settled_at, :utc_datetime
      add :is_private, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:debts, [:contact_id])
    create index(:debts, [:account_id])
    create index(:debts, [:account_id, :status])

    create table(:debt_payments) do
      add :debt_id, references(:debts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :amount, :decimal, precision: 12, scale: 2, null: false
      add :paid_at, :date, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:debt_payments, [:debt_id])
    create index(:debt_payments, [:account_id])
  end
end
