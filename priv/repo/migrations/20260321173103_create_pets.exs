defmodule Kith.Repo.Migrations.CreatePets do
  use Ecto.Migration

  def change do
    create table(:pets) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :species, :string, default: "dog", null: false
      add :breed, :string
      add :date_of_birth, :date
      add :date_of_death, :date
      add :notes, :text
      add :is_private, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pets, [:contact_id])
    create index(:pets, [:account_id])
  end
end
