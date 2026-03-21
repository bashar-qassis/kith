defmodule Kith.Repo.Migrations.AddPrivacyAndAliasFields do
  use Ecto.Migration

  def change do
    # Add aliases to contacts
    alter table(:contacts) do
      add :aliases, {:array, :string}, default: [], null: false
    end

    # Add privacy and creator fields to entities that lack them
    alter table(:activities) do
      add :is_private, :boolean, default: false, null: false
      add :creator_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:calls) do
      add :is_private, :boolean, default: false, null: false
      add :creator_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:life_events) do
      add :is_private, :boolean, default: false, null: false
      add :creator_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:documents) do
      add :is_private, :boolean, default: false, null: false
      add :creator_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:photos) do
      add :is_private, :boolean, default: false, null: false
      add :creator_id, references(:users, on_delete: :nilify_all)
    end

    # GIN index on aliases array for search
    create index(:contacts, [:aliases], using: :gin)
  end
end
