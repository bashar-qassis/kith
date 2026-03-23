defmodule Kith.Repo.Migrations.SeedReferenceData do
  @moduledoc """
  Populates all global reference/lookup tables with default data.

  Previously in seeds.exs, but the app depends on this data at runtime
  (currency lookups, field types, etc.), so it must be guaranteed by migration.
  Uses ON CONFLICT DO NOTHING — safe for databases already seeded manually.
  """
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO currencies (code, name, symbol, inserted_at, updated_at) VALUES
      ('USD', 'US Dollar', '$', NOW(), NOW()),
      ('EUR', 'Euro', '€', NOW(), NOW()),
      ('GBP', 'British Pound', '£', NOW(), NOW()),
      ('JPY', 'Japanese Yen', '¥', NOW(), NOW()),
      ('CAD', 'Canadian Dollar', 'CA$', NOW(), NOW()),
      ('AUD', 'Australian Dollar', 'A$', NOW(), NOW()),
      ('CHF', 'Swiss Franc', 'CHF', NOW(), NOW()),
      ('CNY', 'Chinese Yuan', '¥', NOW(), NOW()),
      ('INR', 'Indian Rupee', '₹', NOW(), NOW()),
      ('BRL', 'Brazilian Real', 'R$', NOW(), NOW()),
      ('KRW', 'South Korean Won', '₩', NOW(), NOW()),
      ('MXN', 'Mexican Peso', 'MX$', NOW(), NOW()),
      ('SGD', 'Singapore Dollar', 'S$', NOW(), NOW()),
      ('HKD', 'Hong Kong Dollar', 'HK$', NOW(), NOW()),
      ('NOK', 'Norwegian Krone', 'kr', NOW(), NOW()),
      ('SEK', 'Swedish Krona', 'kr', NOW(), NOW()),
      ('DKK', 'Danish Krone', 'kr', NOW(), NOW()),
      ('NZD', 'New Zealand Dollar', 'NZ$', NOW(), NOW()),
      ('ZAR', 'South African Rand', 'R', NOW(), NOW()),
      ('RUB', 'Russian Ruble', '₽', NOW(), NOW()),
      ('TRY', 'Turkish Lira', '₺', NOW(), NOW()),
      ('PLN', 'Polish Zloty', 'zł', NOW(), NOW()),
      ('THB', 'Thai Baht', '฿', NOW(), NOW()),
      ('IDR', 'Indonesian Rupiah', 'Rp', NOW(), NOW()),
      ('CZK', 'Czech Koruna', 'Kč', NOW(), NOW()),
      ('ILS', 'Israeli Shekel', '₪', NOW(), NOW()),
      ('PHP', 'Philippine Peso', '₱', NOW(), NOW()),
      ('TWD', 'Taiwan Dollar', 'NT$', NOW(), NOW()),
      ('ARS', 'Argentine Peso', 'AR$', NOW(), NOW()),
      ('CLP', 'Chilean Peso', 'CL$', NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """

    execute """
    INSERT INTO genders (name, account_id, position, inserted_at, updated_at) VALUES
      ('Male', NULL, 0, NOW(), NOW()),
      ('Female', NULL, 1, NOW(), NOW()),
      ('Non-binary', NULL, 2, NOW(), NOW()),
      ('Other', NULL, 3, NOW(), NOW())
    ON CONFLICT DO NOTHING
    """

    execute """
    INSERT INTO emotions (name, account_id, position, inserted_at, updated_at) VALUES
      ('Happy', NULL, 0, NOW(), NOW()),
      ('Grateful', NULL, 1, NOW(), NOW()),
      ('Relaxed', NULL, 2, NOW(), NOW()),
      ('Content', NULL, 3, NOW(), NOW()),
      ('Excited', NULL, 4, NOW(), NOW()),
      ('Proud', NULL, 5, NOW(), NOW()),
      ('Amused', NULL, 6, NOW(), NOW()),
      ('Hopeful', NULL, 7, NOW(), NOW()),
      ('Neutral', NULL, 8, NOW(), NOW()),
      ('Surprised', NULL, 9, NOW(), NOW()),
      ('Confused', NULL, 10, NOW(), NOW()),
      ('Anxious', NULL, 11, NOW(), NOW()),
      ('Sad', NULL, 12, NOW(), NOW()),
      ('Angry', NULL, 13, NOW(), NOW()),
      ('Frustrated', NULL, 14, NOW(), NOW()),
      ('Disappointed', NULL, 15, NOW(), NOW()),
      ('Lonely', NULL, 16, NOW(), NOW()),
      ('Stressed', NULL, 17, NOW(), NOW()),
      ('Guilty', NULL, 18, NOW(), NOW()),
      ('Jealous', NULL, 19, NOW(), NOW())
    ON CONFLICT DO NOTHING
    """

    execute """
    INSERT INTO activity_type_categories (name, icon, account_id, position, inserted_at, updated_at) VALUES
      ('Ate out', 'utensils', NULL, 0, NOW(), NOW()),
      ('Went to a movie', 'film', NULL, 1, NOW(), NOW()),
      ('Went for a walk', 'footprints', NULL, 2, NOW(), NOW()),
      ('Went to a concert', 'music', NULL, 3, NOW(), NOW()),
      ('Played a sport', 'trophy', NULL, 4, NOW(), NOW()),
      ('Had a drink', 'wine', NULL, 5, NOW(), NOW()),
      ('Had coffee', 'coffee', NULL, 6, NOW(), NOW()),
      ('Cooked together', 'chef-hat', NULL, 7, NOW(), NOW()),
      ('Traveled together', 'plane', NULL, 8, NOW(), NOW()),
      ('Video call', 'video', NULL, 9, NOW(), NOW()),
      ('Gift exchange', 'gift', NULL, 10, NOW(), NOW()),
      ('Other', 'ellipsis', NULL, 11, NOW(), NOW())
    ON CONFLICT DO NOTHING
    """

    execute """
    INSERT INTO life_event_types (name, icon, category, account_id, position, inserted_at, updated_at) VALUES
      ('New job', 'briefcase', 'Career', NULL, 0, NOW(), NOW()),
      ('Promotion', 'trending-up', 'Career', NULL, 1, NOW(), NOW()),
      ('Retirement', 'sunset', 'Career', NULL, 2, NOW(), NOW()),
      ('Graduation', 'graduation-cap', 'Education', NULL, 3, NOW(), NOW()),
      ('Started school', 'book-open', 'Education', NULL, 4, NOW(), NOW()),
      ('Birth of a child', 'baby', 'Family', NULL, 5, NOW(), NOW()),
      ('Engagement', 'ring', 'Family', NULL, 6, NOW(), NOW()),
      ('Marriage', 'heart', 'Family', NULL, 7, NOW(), NOW()),
      ('Divorce', 'heart-crack', 'Family', NULL, 8, NOW(), NOW()),
      ('Death of a loved one', 'flower-2', 'Family', NULL, 9, NOW(), NOW()),
      ('Adoption', 'hand-heart', 'Family', NULL, 10, NOW(), NOW()),
      ('Surgery', 'stethoscope', 'Health', NULL, 11, NOW(), NOW()),
      ('Diagnosis', 'clipboard', 'Health', NULL, 12, NOW(), NOW()),
      ('Recovery', 'heart-pulse', 'Health', NULL, 13, NOW(), NOW()),
      ('Moved', 'home', 'Home', NULL, 14, NOW(), NOW()),
      ('Bought a house', 'key', 'Home', NULL, 15, NOW(), NOW()),
      ('Trip', 'map-pin', 'Travel', NULL, 16, NOW(), NOW()),
      ('Moved abroad', 'globe', 'Travel', NULL, 17, NOW(), NOW()),
      ('Other', 'star', 'Other', NULL, 18, NOW(), NOW())
    ON CONFLICT DO NOTHING
    """

    execute """
    INSERT INTO contact_field_types (name, protocol, icon, vcard_label, account_id, position, inserted_at, updated_at) VALUES
      ('Email', 'mailto:', 'mail', 'EMAIL', NULL, 0, NOW(), NOW()),
      ('Phone', 'tel:', 'phone', 'TEL', NULL, 1, NOW(), NOW()),
      ('Mobile', 'tel:', 'smartphone', 'TEL;TYPE=CELL', NULL, 2, NOW(), NOW()),
      ('Work phone', 'tel:', 'phone', 'TEL;TYPE=WORK', NULL, 3, NOW(), NOW()),
      ('Fax', 'tel:', 'printer', 'TEL;TYPE=FAX', NULL, 4, NOW(), NOW()),
      ('Website', 'https://', 'globe', 'URL', NULL, 5, NOW(), NOW()),
      ('Twitter', 'https://twitter.com/', 'twitter', NULL, NULL, 6, NOW(), NOW()),
      ('Facebook', 'https://facebook.com/', 'facebook', NULL, NULL, 7, NOW(), NOW()),
      ('LinkedIn', 'https://linkedin.com/in/', 'linkedin', NULL, NULL, 8, NOW(), NOW()),
      ('Instagram', 'https://instagram.com/', 'instagram', NULL, NULL, 9, NOW(), NOW()),
      ('Telegram', 'https://t.me/', 'send', NULL, NULL, 10, NOW(), NOW()),
      ('WhatsApp', 'https://wa.me/', 'message-circle', NULL, NULL, 11, NOW(), NOW())
    ON CONFLICT DO NOTHING
    """

    execute """
    INSERT INTO relationship_types (name, reverse_name, is_bidirectional, account_id, position, inserted_at, updated_at) VALUES
      ('Partner', 'Partner', true, NULL, 0, NOW(), NOW()),
      ('Spouse', 'Spouse', true, NULL, 1, NOW(), NOW()),
      ('Friend', 'Friend', true, NULL, 2, NOW(), NOW()),
      ('Best friend', 'Best friend', true, NULL, 3, NOW(), NOW()),
      ('Parent', 'Child', false, NULL, 4, NOW(), NOW()),
      ('Child', 'Parent', false, NULL, 5, NOW(), NOW()),
      ('Sibling', 'Sibling', true, NULL, 6, NOW(), NOW()),
      ('Grandparent', 'Grandchild', false, NULL, 7, NOW(), NOW()),
      ('Grandchild', 'Grandparent', false, NULL, 8, NOW(), NOW()),
      ('Uncle/Aunt', 'Nephew/Niece', false, NULL, 9, NOW(), NOW()),
      ('Nephew/Niece', 'Uncle/Aunt', false, NULL, 10, NOW(), NOW()),
      ('Cousin', 'Cousin', true, NULL, 11, NOW(), NOW()),
      ('Colleague', 'Colleague', true, NULL, 12, NOW(), NOW()),
      ('Boss', 'Subordinate', false, NULL, 13, NOW(), NOW()),
      ('Subordinate', 'Boss', false, NULL, 14, NOW(), NOW()),
      ('Mentor', 'Mentee', false, NULL, 15, NOW(), NOW()),
      ('Mentee', 'Mentor', false, NULL, 16, NOW(), NOW()),
      ('Neighbor', 'Neighbor', true, NULL, 17, NOW(), NOW()),
      ('Roommate', 'Roommate', true, NULL, 18, NOW(), NOW()),
      ('Ex-partner', 'Ex-partner', true, NULL, 19, NOW(), NOW())
    ON CONFLICT DO NOTHING
    """

    execute """
    INSERT INTO call_directions (name, position, inserted_at, updated_at) VALUES
      ('Inbound', 0, NOW(), NOW()),
      ('Outbound', 1, NOW(), NOW()),
      ('Missed', 2, NOW(), NOW())
    ON CONFLICT (name) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM call_directions"
    execute "DELETE FROM relationship_types WHERE account_id IS NULL"
    execute "DELETE FROM contact_field_types WHERE account_id IS NULL"
    execute "DELETE FROM life_event_types WHERE account_id IS NULL"
    execute "DELETE FROM activity_type_categories WHERE account_id IS NULL"
    execute "DELETE FROM emotions WHERE account_id IS NULL"
    execute "DELETE FROM genders WHERE account_id IS NULL"
    execute "DELETE FROM currencies"
  end
end
