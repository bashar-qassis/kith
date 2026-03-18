defmodule Kith.Repo.Migrations.CreateImmichCandidates do
  use Ecto.Migration

  def change do
    create table(:immich_candidates) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :immich_photo_id, :string, null: false
      add :immich_server_url, :string, null: false
      add :thumbnail_url, :string, null: false
      add :suggested_at, :utc_datetime, null: false
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create constraint(:immich_candidates, :immich_candidates_status_values,
             check: "status IN ('pending', 'accepted', 'rejected')"
           )

    create unique_index(:immich_candidates, [:contact_id, :immich_photo_id])
    create index(:immich_candidates, [:account_id])
  end
end
