defmodule Kith.Repo.Migrations.AddImppContactFieldType do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO contact_field_types (name, protocol, icon, vcard_label, account_id, position, inserted_at, updated_at)
    VALUES ('IMPP', 'impp:', 'message-square', 'IMPP', NULL, 12, NOW(), NOW())
    ON CONFLICT DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM contact_field_types WHERE name = 'IMPP' AND protocol = 'impp:' AND account_id IS NULL"
  end
end
