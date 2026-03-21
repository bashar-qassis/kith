defmodule Kith.Repo.Migrations.AddFirstMetFieldsToContacts do
  use Ecto.Migration

  def change do
    alter table(:contacts) do
      add :middle_name, :string
      add :first_met_at, :date
      add :first_met_year_unknown, :boolean, default: false, null: false
      add :first_met_where, :string
      add :first_met_through_id, references(:contacts, on_delete: :nilify_all)
      add :first_met_additional_info, :text
      add :birthdate_year_unknown, :boolean, default: false, null: false
    end

    create index(:contacts, [:first_met_through_id])
  end
end
