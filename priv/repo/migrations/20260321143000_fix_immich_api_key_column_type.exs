defmodule Kith.Repo.Migrations.FixImmichApiKeyColumnType do
  use Ecto.Migration

  def up do
    # Cloak-encrypted fields must be stored as bytea, not varchar.
    # Existing data (if any) is plaintext and will be lost on type change,
    # but this column has not been used in production yet.
    execute "ALTER TABLE accounts ALTER COLUMN immich_api_key TYPE bytea USING NULL"
  end

  def down do
    execute "ALTER TABLE accounts ALTER COLUMN immich_api_key TYPE varchar USING NULL"
  end
end
