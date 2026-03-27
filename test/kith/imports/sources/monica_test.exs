defmodule Kith.Imports.Sources.MonicaTest do
  use Kith.DataCase, async: true

  alias Kith.Imports.Sources.Monica, as: MonicaSource
  alias Kith.Imports
  alias Kith.Contacts
  alias Kith.Repo

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures
  import Kith.ImportsFixtures

  @fixture_path Path.join([
                  __DIR__,
                  "..",
                  "..",
                  "..",
                  "support",
                  "fixtures",
                  "monica_export.json"
                ])

  setup do
    user = user_fixture()
    seed_reference_data!()
    %{user: user, account_id: user.account_id}
  end

  describe "name/0" do
    test "returns source name" do
      assert MonicaSource.name() == "Monica CRM"
    end
  end

  describe "file_types/0" do
    test "returns accepted file types" do
      assert MonicaSource.file_types() == [".json"]
    end
  end

  describe "supports_api?/0" do
    test "returns true" do
      assert MonicaSource.supports_api?()
    end
  end

  describe "validate_file/1" do
    test "validates a proper Monica export" do
      data = File.read!(@fixture_path)
      assert {:ok, %{}} = MonicaSource.validate_file(data)
    end

    test "rejects invalid JSON" do
      assert {:error, "File is not valid JSON"} = MonicaSource.validate_file("not json {{{")
    end

    test "rejects JSON missing required keys" do
      data = Jason.encode!(%{"something" => "else"})
      assert {:error, msg} = MonicaSource.validate_file(data)
      assert msg =~ "missing required"
    end

    test "accepts minimal valid structure" do
      data = Jason.encode!(%{"contacts" => %{"data" => []}, "account" => %{"data" => %{}}})
      assert {:ok, %{}} = MonicaSource.validate_file(data)
    end
  end

  describe "parse_summary/1" do
    test "returns entity counts", _context do
      data = File.read!(@fixture_path)
      assert {:ok, summary} = MonicaSource.parse_summary(data)

      assert summary.contacts == 2
      assert summary.relationships == 1
      assert summary.notes == 2
      assert summary.photos == 2
      # The shared activity is deduped
      assert summary.activities == 1
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = MonicaSource.parse_summary("not json")
    end
  end

  describe "import/4" do
    test "imports contacts with all children", %{account_id: account_id, user: user} do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@fixture_path)

      assert {:ok, summary} =
               MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      # 2 contacts imported
      assert summary.contacts == 2

      # Verify Alice was created
      alice_record =
        Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-alice")

      assert alice_record
      alice = Repo.get!(Contacts.Contact, alice_record.local_entity_id)
      assert alice.first_name == "Alice"
      assert alice.last_name == "Johnson"
      assert alice.middle_name == "Marie"
      assert alice.nickname == "AJ"
      assert alice.description == "College friend"
      assert alice.company == "Acme Corp"
      assert alice.occupation == "Software Engineer"
      assert alice.favorite == true
      assert alice.is_archived == false
      assert alice.deceased == false
      assert alice.birthdate == ~D[1990-06-15]
      assert alice.first_met_at == ~D[2015-09-01]

      # Verify Bob was created with inverted flags
      bob_record = Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-bob")
      assert bob_record
      bob = Repo.get!(Contacts.Contact, bob_record.local_entity_id)
      assert bob.first_name == "Bob"
      assert bob.last_name == "Smith"
      assert bob.is_archived == true
      assert bob.deceased == true
      assert bob.birthdate == ~D[0001-03-20]
      assert bob.birthdate_year_unknown == true

      # Verify gender assignment
      assert alice.gender_id != nil
      assert bob.gender_id != nil
      assert alice.gender_id != bob.gender_id

      # Verify contact fields
      alice_cf =
        Imports.find_import_record(account_id, "monica", "contact_field", "cf-uuid-alice-email")

      assert alice_cf

      bob_cf =
        Imports.find_import_record(account_id, "monica", "contact_field", "cf-uuid-bob-phone")

      assert bob_cf

      # Verify addresses
      alice_addr = Imports.find_import_record(account_id, "monica", "address", "addr-uuid-alice")
      assert alice_addr

      # Verify notes
      assert summary.notes == 2
      alice_note = Imports.find_import_record(account_id, "monica", "note", "note-uuid-alice")
      assert alice_note

      # Verify pets
      alice_pet = Imports.find_import_record(account_id, "monica", "pet", "pet-uuid-alice-dog")
      assert alice_pet
      bob_pet = Imports.find_import_record(account_id, "monica", "pet", "pet-uuid-bob-iguana")
      assert bob_pet
      # Lizard should map to "other"
      pet = Repo.get!(Kith.Contacts.Pet, bob_pet.local_entity_id)
      assert pet.species == "other"

      # Verify photos with pending_sync storage keys
      alice_photo =
        Imports.find_import_record(account_id, "monica", "photo", "photo-uuid-alice-1")

      assert alice_photo
      photo = Repo.get!(Contacts.Photo, alice_photo.local_entity_id)
      assert photo.storage_key == "pending_sync:photo-uuid-alice-1"
      assert photo.file_name == "alice_profile.jpg"
      assert Contacts.Photo.pending_sync?(photo)

      # Verify the shared activity was created once (deduplication)
      activity_record =
        Imports.find_import_record(account_id, "monica", "activity", "activity-uuid-shared")

      assert activity_record
      activity = Repo.get!(Kith.Activities.Activity, activity_record.local_entity_id)
      assert activity.title == "Coffee at Blue Bottle"

      # Both contacts should be linked to the activity
      activity_contacts =
        from(ac in "activity_contacts",
          where: ac.activity_id == ^activity.id,
          select: ac.contact_id
        )
        |> Repo.all()

      assert length(activity_contacts) == 2
      assert alice_record.local_entity_id in activity_contacts
      assert bob_record.local_entity_id in activity_contacts
    end

    test "creates import_records for deduplication", %{account_id: account_id, user: user} do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@fixture_path)

      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      # Verify import records exist for all entity types
      assert Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-alice")
      assert Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-bob")
      assert Imports.find_import_record(account_id, "monica", "note", "note-uuid-alice")
      assert Imports.find_import_record(account_id, "monica", "note", "note-uuid-bob")
      assert Imports.find_import_record(account_id, "monica", "photo", "photo-uuid-alice-1")
      assert Imports.find_import_record(account_id, "monica", "photo", "photo-uuid-bob-1")
      assert Imports.find_import_record(account_id, "monica", "activity", "activity-uuid-shared")
      assert Imports.find_import_record(account_id, "monica", "relationship", "rel-uuid-001")
    end

    test "handles re-import (upsert)", %{account_id: account_id, user: user} do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@fixture_path)

      # First import
      {:ok, first_summary} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})
      assert first_summary.contacts == 2

      alice_record =
        Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-alice")

      alice = Repo.get!(Contacts.Contact, alice_record.local_entity_id)
      assert alice.first_name == "Alice"

      # Modify export data to change Alice's description
      parsed = Jason.decode!(data)
      contacts = get_in(parsed, ["contacts", "data"])

      updated_contacts =
        Enum.map(contacts, fn c ->
          if c["uuid"] == "contact-uuid-alice" do
            Map.put(c, "description", "Updated description")
          else
            c
          end
        end)

      updated_data = put_in(parsed, ["contacts", "data"], updated_contacts) |> Jason.encode!()

      # Complete first import so we can create second
      Imports.update_import_status(import_rec, "completed")

      # Second import
      import_rec2 = import_fixture(account_id, user.id)

      {:ok, second_summary} =
        MonicaSource.import(account_id, user.id, updated_data, %{import: import_rec2})

      assert second_summary.contacts == 2

      # Verify Alice was updated
      alice_updated = Repo.get!(Contacts.Contact, alice_record.local_entity_id)
      assert alice_updated.description == "Updated description"
    end

    test "resolves first_met_through cross-references", %{account_id: account_id, user: user} do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@fixture_path)

      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      # Bob has first_met_through = "contact-uuid-alice"
      bob_record = Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-bob")

      alice_record =
        Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-alice")

      bob = Repo.get!(Contacts.Contact, bob_record.local_entity_id)
      assert bob.first_met_through_id == alice_record.local_entity_id
    end

    test "creates relationships between contacts", %{account_id: account_id, user: user} do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@fixture_path)

      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      # Verify relationship was created
      rel_record =
        Imports.find_import_record(account_id, "monica", "relationship", "rel-uuid-001")

      assert rel_record

      relationship = Repo.get!(Contacts.Relationship, rel_record.local_entity_id)

      alice_record =
        Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-alice")

      bob_record = Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-bob")

      assert relationship.contact_id == alice_record.local_entity_id
      assert relationship.related_contact_id == bob_record.local_entity_id
    end

    test "imports tags and creates join entries", %{account_id: account_id, user: user} do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@fixture_path)

      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      alice_record =
        Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-alice")

      bob_record = Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-bob")

      # Alice has 1 tag: Friends
      alice_tags =
        from(ct in "contact_tags",
          where: ct.contact_id == ^alice_record.local_entity_id,
          select: ct.tag_id
        )
        |> Repo.all()

      assert length(alice_tags) == 1

      # Bob has 2 tags: Friends, Work
      bob_tags =
        from(ct in "contact_tags",
          where: ct.contact_id == ^bob_record.local_entity_id,
          select: ct.tag_id
        )
        |> Repo.all()

      assert length(bob_tags) == 2
    end

    test "maps pet species correctly", %{account_id: account_id, user: user} do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@fixture_path)

      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      # Alice's pet is a Dog -> "dog"
      alice_pet_rec =
        Imports.find_import_record(account_id, "monica", "pet", "pet-uuid-alice-dog")

      alice_pet = Repo.get!(Kith.Contacts.Pet, alice_pet_rec.local_entity_id)
      assert alice_pet.name == "Buddy"
      assert alice_pet.species == "dog"

      # Bob's pet is a Lizard -> "other" (not in known mapping)
      bob_pet_rec = Imports.find_import_record(account_id, "monica", "pet", "pet-uuid-bob-iguana")
      bob_pet = Repo.get!(Kith.Contacts.Pet, bob_pet_rec.local_entity_id)
      assert bob_pet.name == "Scales"
      assert bob_pet.species == "other"
    end

    test "imports without import record (no tracking)", %{account_id: account_id, user: user} do
      data = File.read!(@fixture_path)

      # Import without passing an import record
      assert {:ok, summary} = MonicaSource.import(account_id, user.id, data, %{})
      assert summary.contacts == 2
    end

    test "returns error for invalid JSON", %{account_id: account_id, user: user} do
      assert {:error, "File is not valid JSON"} =
               MonicaSource.import(account_id, user.id, "not json", %{})
    end

    test "creates reminders for contacts", %{account_id: account_id, user: user} do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@fixture_path)

      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      # Alice has a reminder
      reminder_rec =
        Imports.find_import_record(account_id, "monica", "reminder", "reminder-uuid-alice")

      assert reminder_rec
      reminder = Repo.get!(Kith.Reminders.Reminder, reminder_rec.local_entity_id)
      assert reminder.title == "Alice's birthday"
    end
  end

  describe "v4 format import with duplicate contact entries" do
    @v4_fixture_path Path.join([
                       __DIR__,
                       "..",
                       "..",
                       "..",
                       "support",
                       "fixtures",
                       "monica_v4_export.json"
                     ])

    test "merges photo references from duplicate entries", %{
      account_id: account_id,
      user: user
    } do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@v4_fixture_path)

      assert {:ok, summary} =
               MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      assert summary.contacts == 2

      # Carol's photo should be imported even though it was on the older entry
      carol_photo =
        Imports.find_import_record(account_id, "monica", "photo", "photo-uuid-carol-1")

      assert carol_photo, "Carol's photo should survive dedup merge"

      # Dave's photo should also be imported (single entry, no dedup)
      dave_photo =
        Imports.find_import_record(account_id, "monica", "photo", "photo-uuid-dave-1")

      assert dave_photo, "Dave's photo should be imported"
    end

    test "uses properties from the latest entry when merging", %{
      account_id: account_id,
      user: user
    } do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@v4_fixture_path)

      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      carol_rec =
        Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-carol")

      carol = Repo.get!(Contacts.Contact, carol_rec.local_entity_id)
      assert carol.last_name == "Newer"
    end

    test "deduplicates sub-data values by UUID when merging", %{
      account_id: account_id,
      user: user
    } do
      import_rec = import_fixture(account_id, user.id)
      data = File.read!(@v4_fixture_path)

      {:ok, summary} = MonicaSource.import(account_id, user.id, data, %{import: import_rec})

      # Carol has 3 unique notes (note-uuid-1 and note-uuid-2 overlap between entries)
      assert summary.notes == 3
    end
  end

  describe "api_supplement_options/0" do
    test "returns available supplement options" do
      options = MonicaSource.api_supplement_options()
      assert length(options) == 2
      keys = Enum.map(options, & &1.key)
      assert :photos in keys
      assert :first_met_details in keys
    end
  end
end
