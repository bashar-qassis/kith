defmodule Kith.Repo.Migrations.AddContentHashToPhotos do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :content_hash, :string
    end

    create unique_index(:photos, [:contact_id, :content_hash],
      where: "content_hash IS NOT NULL",
      name: :photos_contact_content_hash_idx
    )
  end
end
