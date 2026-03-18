defmodule Kith.Repo.Migrations.CreateWebauthnCredentials do
  use Ecto.Migration

  def change do
    create table(:webauthn_credentials) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :integer, null: false, default: 0
      add :name, :string, null: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:webauthn_credentials, [:user_id])
    create unique_index(:webauthn_credentials, [:credential_id])
  end
end
