defmodule Kith.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    # ── accounts ──────────────────────────────────────────────────────
    create table(:accounts) do
      add :name, :string
      add :timezone, :string, default: "Etc/UTC"
      add :locale, :string, default: "en"
      add :send_hour, :integer, default: 8

      # Immich integration (Phase 07 — columns created now for ERD alignment)
      add :immich_base_url, :string
      add :immich_api_key, :string
      add :immich_status, :string, default: "unconfigured"
      add :immich_consecutive_failures, :integer, default: 0
      add :immich_last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # ── users ─────────────────────────────────────────────────────────
    create table(:users) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :role, :string, null: false, default: "editor"
      add :is_active, :boolean, null: false, default: true

      # Profile preferences (ERD columns)
      add :display_name, :string
      add :timezone, :string
      add :locale, :string
      add :currency, :string, default: "USD"
      add :temperature_unit, :string, default: "celsius"

      # me_contact_id — FK to contacts table (created in Phase 04)
      # Using a raw bigint now; the FK constraint is added in a later migration
      add :me_contact_id, :bigint

      # Email confirmation
      add :confirmed_at, :utc_datetime

      # TOTP two-factor authentication (Phase 02 — TASK-02-05)
      add :totp_secret, :binary
      add :totp_enabled, :boolean, null: false, default: false

      # WebAuthn (Phase 02 — TASK-02-09)
      add :webauthn_enabled, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create index(:users, [:account_id])

    # ── user_tokens ───────────────────────────────────────────────────
    create table(:user_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:user_tokens, [:user_id])
    create unique_index(:user_tokens, [:context, :token])
  end
end
