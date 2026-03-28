defmodule Kith.Repo.Migrations.AddSyncSummaryToImports do
  use Ecto.Migration

  def change do
    alter table(:imports) do
      add :sync_summary, :map
    end
  end
end
