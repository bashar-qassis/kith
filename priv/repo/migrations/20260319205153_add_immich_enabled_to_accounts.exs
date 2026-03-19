defmodule Kith.Repo.Migrations.AddImmichEnabledToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :immich_enabled, :boolean, null: false, default: false
    end
  end
end
