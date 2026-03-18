defmodule Kith.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :uid, :string, null: false
      add :access_token, :binary
      add :access_token_secret, :binary
      add :refresh_token, :binary
      add :token_url, :string
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:user_identities, [:user_id])
    create unique_index(:user_identities, [:provider, :uid])
  end
end
