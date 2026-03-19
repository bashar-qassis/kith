defmodule Kith.Repo.Migrations.CreateAccountInvitations do
  use Ecto.Migration

  def change do
    create table(:account_invitations) do
      add :email, :string, null: false
      add :token_hash, :binary, null: false
      add :role, :string, null: false, default: "viewer"
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:account_invitations, [:account_id, :email],
             where: "accepted_at IS NULL",
             name: :account_invitations_pending_email_idx
           )

    create index(:account_invitations, [:token_hash])
    create index(:account_invitations, [:account_id])
  end
end
