defmodule Kith.Repo.Migrations.RemoveIsCoverFromPhotos do
  use Ecto.Migration

  def up do
    # Migrate existing cover photos to contact.avatar before dropping the column
    execute("""
    UPDATE contacts SET avatar = p.storage_key
    FROM photos p
    WHERE p.contact_id = contacts.id
      AND p.is_cover = true
      AND p.storage_key NOT LIKE 'pending_sync:%'
      AND contacts.avatar IS NULL
    """)

    drop_if_exists unique_index(:photos, [:contact_id],
                     where: "is_cover = true",
                     name: :photos_contact_id_index
                   )

    alter table(:photos) do
      remove :is_cover
    end
  end

  def down do
    alter table(:photos) do
      add :is_cover, :boolean, null: false, default: false
    end

    create unique_index(:photos, [:contact_id],
             where: "is_cover = true",
             name: :photos_contact_id_index
           )
  end
end
