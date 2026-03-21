defmodule Kith.Repo.Migrations.CreateGifts do
  use Ecto.Migration

  def change do
    create table(:gifts) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :creator_id, references(:users, on_delete: :nilify_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :occasion, :string
      add :date, :date
      add :amount, :decimal, precision: 12, scale: 2
      add :currency_id, references(:currencies, on_delete: :nilify_all)
      add :direction, :string, null: false
      add :status, :string, default: "idea", null: false
      add :purchase_url, :string
      add :is_private, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:gifts, [:contact_id])
    create index(:gifts, [:account_id])
    create index(:gifts, [:account_id, :status])
  end
end
