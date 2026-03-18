defmodule Kith.Repo.Migrations.AlignAccountsUsersWithErd do
  use Ecto.Migration

  def change do
    # ── accounts fixes ─────────────────────────────────────────────────
    alter table(:accounts) do
      # ERD: name NOT NULL
      modify :name, :string, null: false, from: {:string, null: true}

      # ERD: send_hour default 9 (was 8)
      modify :send_hour, :integer,
        null: false,
        default: 9,
        from: {:integer, null: true, default: 8}

      # ERD: immich_status default 'disabled' (was 'unconfigured')
      modify :immich_status, :string,
        null: false,
        default: "disabled",
        from: {:string, null: true, default: "unconfigured"}

      # ERD: feature_flags jsonb NOT NULL default '{}'
      add :feature_flags, :map, null: false, default: %{}
    end

    # CHECK constraint on send_hour
    create constraint(:accounts, :accounts_send_hour_range,
             check: "send_hour >= 0 AND send_hour <= 23"
           )

    # CHECK constraint on immich_status
    create constraint(:accounts, :accounts_immich_status_values,
             check: "immich_status IN ('disabled', 'ok', 'error')"
           )

    # ── users fixes ────────────────────────────────────────────────────
    alter table(:users) do
      # ERD: role default 'admin' (was 'editor')
      modify :role, :string,
        null: false,
        default: "admin",
        from: {:string, null: false, default: "editor"}

      # Drop is_active — not in ERD
      remove :is_active, :boolean, default: true, null: false

      # Plan additions: display_name_format and default_profile_tab
      add :display_name_format, :string
      add :default_profile_tab, :string, default: "notes"
    end

    # CHECK constraint on role
    create constraint(:users, :users_role_values, check: "role IN ('admin', 'editor', 'viewer')")

    # CHECK constraint on temperature_unit
    create constraint(:users, :users_temperature_unit_values,
             check: "temperature_unit IN ('celsius', 'fahrenheit')"
           )
  end
end
