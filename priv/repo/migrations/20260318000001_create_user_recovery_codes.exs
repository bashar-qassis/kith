defmodule Kith.Repo.Migrations.CreateUserRecoveryCodes do
  use Ecto.Migration

  def change do
    create table(:user_recovery_codes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :hashed_code, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:user_recovery_codes, [:user_id])
  end
end
