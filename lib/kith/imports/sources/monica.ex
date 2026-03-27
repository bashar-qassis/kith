defmodule Kith.Imports.Sources.Monica do
  @moduledoc """
  Monica CRM import source.

  Parses a Monica JSON export and imports contacts with all associated data:
  contact fields, addresses, notes, reminders, pets, photos, activities,
  relationships, and first-met cross-references.
  """

  @behaviour Kith.Imports.Source

  import Ecto.Query, warn: false

  alias Kith.Contacts
  alias Kith.Imports
  alias Kith.Repo

  require Logger

  # ── Behaviour callbacks ───────────────────────────────────────────────

  @impl true
  def name, do: "Monica CRM"

  @impl true
  def file_types, do: [".json"]

  @impl true
  def supports_api?, do: true

  @impl true
  def validate_file(data) do
    case Jason.decode(data) do
      {:ok, %{"contacts" => _, "account" => _}} ->
        {:ok, %{}}

      {:ok, %{"version" => _, "account" => %{"data" => sections}}} when is_list(sections) ->
        {:ok, %{}}

      {:ok, _} ->
        {:error, "JSON file is missing required \"contacts\" or \"account\" keys"}

      {:error, _} ->
        {:error, "File is not valid JSON"}
    end
  end

  @impl true
  def parse_summary(data) do
    case Jason.decode(data) do
      {:ok, parsed} -> build_summary(parsed)
      {:error, _} -> {:error, "File is not valid JSON"}
    end
  end

  defp build_summary(parsed) do
    normalized = normalize(parsed)
    contacts = get_in(normalized, ["contacts", "data"]) || []
    relationships = get_in(normalized, ["relationships", "data"]) || []

    {notes_count, photos_count, activities_count} =
      Enum.reduce(contacts, {0, 0, MapSet.new()}, &accumulate_contact_summary/2)

    {:ok,
     %{
       contacts: length(contacts),
       relationships: length(relationships),
       notes: notes_count,
       photos: photos_count,
       activities: MapSet.size(activities_count)
     }}
  end

  defp accumulate_contact_summary(contact, {notes, photos, act_set}) do
    n = length(get_in(contact, ["notes", "data"]) || [])
    p = length(get_in(contact, ["photos", "data"]) || [])

    acts = get_in(contact, ["activities", "data"]) || []
    new_act_set = Enum.reduce(acts, act_set, fn a, set -> MapSet.put(set, a["uuid"]) end)

    {notes + n, photos + p, new_act_set}
  end

  @impl true
  def import(account_id, user_id, data, opts) do
    import_record = opts[:import]

    case Jason.decode(data) do
      {:ok, parsed} ->
        normalized = normalize(parsed)
        do_import(account_id, user_id, normalized, import_record)

      {:error, _} ->
        {:error, "File is not valid JSON"}
    end
  end

  @impl true
  def test_connection(%{url: url, api_key: api_key}) do
    headers = [{"Authorization", "Bearer #{api_key}"}, {"Accept", "application/json"}]

    case Req.get("#{url}/api/me", headers: headers) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: 401}} -> {:error, "Invalid API key"}
      {:ok, %{status: status}} -> {:error, "Unexpected status: #{status}"}
      {:error, reason} -> {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def list_photos(%{url: url, api_key: api_key}, page) do
    headers = [{"Authorization", "Bearer #{api_key}"}]

    case Req.get("#{url}/api/photos?page=#{page}", headers: headers) do
      {:ok, %{status: 200, body: %{"data" => photos}}} when is_list(photos) -> {:ok, photos}
      {:ok, %{status: 200, body: _}} -> {:ok, []}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} -> {:error, "Unexpected status: #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def api_supplement_options do
    [
      %{
        key: :photos,
        label: "Sync photos",
        description: "Download photo files from Monica API"
      },
      %{
        key: :first_met_details,
        label: "Fetch \"How we met\" details",
        description: "Import first_met_where and first_met_additional_info from the API"
      }
    ]
  end

  @impl true
  def fetch_supplement(%{url: url, api_key: api_key}, contact_source_id, :first_met_details) do
    headers = [{"Authorization", "Bearer #{api_key}"}, {"Accept", "application/json"}]

    case Req.get("#{url}/api/contacts/#{contact_source_id}", headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        contact_data = body["data"] || body

        {:ok,
         %{
           first_met_where: contact_data["first_met_where"],
           first_met_additional_info: contact_data["first_met_additional_information"]
         }}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_supplement(_credential, _contact_source_id, _key) do
    {:error, :unsupported_supplement}
  end

  # ── Import orchestration ──────────────────────────────────────────────

  defp do_import(account_id, user_id, parsed, import_record) do
    contacts_data = get_in(parsed, ["contacts", "data"]) || []
    relationships_data = get_in(parsed, ["relationships", "data"]) || []

    # Phase 1: Reference data (genders, tags, contact field types, activity type categories)
    ref_data = build_reference_data(account_id, contacts_data)

    # Phase 2+3: Contacts and their children
    {summary, activity_set} =
      import_contacts(account_id, user_id, contacts_data, ref_data, import_record)

    # Phase 4: Cross-contact references (relationships, first_met_through)
    rel_errors = import_relationships(account_id, relationships_data, ref_data, import_record)
    fmt_errors = resolve_first_met_through(account_id, contacts_data, import_record)

    all_errors = summary.errors ++ rel_errors ++ fmt_errors
    error_count = summary.error_count + length(rel_errors) + length(fmt_errors)

    _ = activity_set

    {:ok,
     %{
       imported: summary.contacts,
       contacts: summary.contacts,
       notes: summary.notes,
       skipped: summary.skipped,
       error_count: error_count,
       errors: Enum.take(all_errors, 50)
     }}
  end

  # ── Phase 1: Reference data ──────────────────────────────────────────

  defp build_reference_data(account_id, contacts_data) do
    # Collect all unique genders, tags, contact field types, activity type categories
    genders = collect_genders(contacts_data)
    tags = collect_tags(contacts_data)
    cfts = collect_contact_field_types(contacts_data)
    atcs = collect_activity_type_categories(contacts_data)

    gender_map = find_or_create_genders(account_id, genders)
    tag_map = find_or_create_tags(account_id, tags)
    cft_map = find_or_create_contact_field_types(account_id, cfts)
    atc_map = find_or_create_activity_type_categories(account_id, atcs)

    %{
      genders: gender_map,
      tags: tag_map,
      contact_field_types: cft_map,
      activity_type_categories: atc_map
    }
  end

  defp collect_genders(contacts_data) do
    contacts_data
    |> Enum.map(&get_in(&1, ["gender", "data", "name"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp collect_tags(contacts_data) do
    contacts_data
    |> Enum.flat_map(fn c -> (get_in(c, ["tags", "data"]) || []) |> Enum.map(& &1["name"]) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp collect_contact_field_types(contacts_data) do
    contacts_data
    |> Enum.flat_map(fn c ->
      (get_in(c, ["contact_fields", "data"]) || [])
      |> Enum.map(&get_in(&1, ["contact_field_type", "data", "name"]))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp collect_activity_type_categories(contacts_data) do
    contacts_data
    |> Enum.flat_map(fn c ->
      (get_in(c, ["activities", "data"]) || [])
      |> Enum.map(&get_in(&1, ["activity_type_category", "data", "name"]))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp find_or_create_genders(account_id, names) do
    Map.new(names, fn name ->
      gender =
        Repo.one(
          from(g in Contacts.Gender,
            where: g.name == ^name and (g.account_id == ^account_id or is_nil(g.account_id)),
            limit: 1
          )
        ) || elem(Contacts.create_gender(account_id, %{name: name}), 1)

      {name, gender.id}
    end)
  end

  defp find_or_create_tags(account_id, names) do
    Map.new(names, fn name ->
      tag =
        Repo.one(
          from(t in Contacts.Tag,
            where: t.name == ^name and t.account_id == ^account_id,
            limit: 1
          )
        ) || elem(Contacts.create_tag(account_id, %{name: name}), 1)

      {name, tag.id}
    end)
  end

  defp find_or_create_contact_field_types(account_id, names) do
    Map.new(names, fn name ->
      cft =
        Repo.one(
          from(t in Contacts.ContactFieldType,
            where: t.name == ^name and (t.account_id == ^account_id or is_nil(t.account_id)),
            limit: 1
          )
        ) || elem(Contacts.create_contact_field_type(account_id, %{name: name}), 1)

      {name, cft.id}
    end)
  end

  defp find_or_create_activity_type_categories(account_id, names) do
    Map.new(names, fn name ->
      atc =
        Repo.one(
          from(a in Contacts.ActivityTypeCategory,
            where: a.name == ^name and (a.account_id == ^account_id or is_nil(a.account_id)),
            limit: 1
          )
        ) || elem(Contacts.create_activity_type_category(account_id, %{name: name}), 1)

      {name, atc.id}
    end)
  end

  # ── Phase 2+3: Contacts and children ─────────────────────────────────

  defp import_contacts(account_id, user_id, contacts_data, ref_data, import_record) do
    initial_acc = %{
      contacts: 0,
      notes: 0,
      skipped: 0,
      error_count: 0,
      errors: [],
      activity_set: MapSet.new()
    }

    total = length(contacts_data)
    topic = "import:#{account_id}"
    broadcast_interval = max(1, div(total, 50))

    result =
      contacts_data
      |> Enum.with_index(1)
      |> Enum.reduce(initial_acc, fn {contact_data, idx}, acc ->
        maybe_check_import_cancelled(import_record, idx)

        result =
          safe_import_single_contact(
            account_id,
            user_id,
            contact_data,
            ref_data,
            import_record,
            acc
          )

        maybe_broadcast_import_progress(topic, idx, total, broadcast_interval)
        result
      end)

    summary = Map.drop(result, [:activity_set])
    {summary, result.activity_set}
  catch
    :cancelled ->
      {%{contacts: 0, notes: 0, skipped: 0, error_count: 0, errors: ["Import cancelled"]},
       MapSet.new()}
  end

  defp maybe_check_import_cancelled(import_record, idx) do
    if import_record && rem(idx, 10) == 0 do
      refreshed = Imports.get_import!(import_record.id)
      if refreshed.status == "cancelled", do: throw(:cancelled)
    end
  end

  defp safe_import_single_contact(account_id, user_id, contact_data, ref_data, import_record, acc) do
    import_single_contact(account_id, user_id, contact_data, ref_data, import_record, acc)
  rescue
    e ->
      name = contact_display_name(contact_data)
      msg = "Contact #{name}: #{Exception.message(e)}"
      Logger.error("[Monica Import] #{msg}")
      add_error(acc, msg)
  end

  defp maybe_broadcast_import_progress(topic, idx, total, broadcast_interval) do
    if rem(idx, broadcast_interval) == 0 || idx == total do
      Phoenix.PubSub.broadcast(
        Kith.PubSub,
        topic,
        {:import_progress, %{current: idx, total: total}}
      )
    end
  end

  defp import_single_contact(account_id, user_id, contact_data, ref_data, import_record, acc) do
    uuid = contact_data["uuid"]

    # Check for existing import record (re-import)
    existing =
      if import_record, do: Imports.find_import_record(account_id, "monica", "contact", uuid)

    case existing do
      %{local_entity_id: local_id} ->
        # Re-import: update existing contact
        case Repo.get(Contacts.Contact, local_id) do
          nil ->
            # Local contact was deleted, re-create
            do_create_contact(account_id, user_id, contact_data, ref_data, import_record, acc)

          %{deleted_at: deleted_at} when not is_nil(deleted_at) ->
            Logger.info(
              "[Monica Import] Skipping #{contact_display_name(contact_data)}: previously deleted in Kith"
            )

            %{acc | skipped: acc.skipped + 1}

          contact ->
            do_update_contact(contact, user_id, contact_data, ref_data, import_record, acc)
        end

      nil ->
        do_create_contact(account_id, user_id, contact_data, ref_data, import_record, acc)
    end
  end

  defp do_create_contact(account_id, user_id, contact_data, ref_data, import_record, acc) do
    attrs = build_contact_attrs(contact_data, ref_data)

    case Contacts.create_contact(account_id, attrs) do
      {:ok, contact} ->
        # Record the import
        if import_record do
          Imports.record_imported_entity(
            import_record,
            "contact",
            contact_data["uuid"],
            "contact",
            contact.id
          )
        end

        # Import children and update accumulator
        import_contact_children(contact, user_id, contact_data, ref_data, import_record, acc)

      {:error, changeset} ->
        name = contact_display_name(contact_data)
        msg = "Contact #{name}: #{inspect_errors(changeset)}"
        Logger.warning("[Monica Import] #{msg}")
        add_error(acc, msg)
    end
  end

  defp do_update_contact(contact, user_id, contact_data, ref_data, import_record, acc) do
    attrs = build_contact_attrs(contact_data, ref_data)

    case Contacts.update_contact(contact, attrs) do
      {:ok, contact} ->
        if import_record do
          Imports.record_imported_entity(
            import_record,
            "contact",
            contact_data["uuid"],
            "contact",
            contact.id
          )
        end

        import_contact_children(contact, user_id, contact_data, ref_data, import_record, acc)

      {:error, changeset} ->
        name = contact_display_name(contact_data)
        msg = "Contact #{name} (update): #{inspect_errors(changeset)}"
        Logger.warning("[Monica Import] #{msg}")
        add_error(acc, msg)
    end
  end

  defp build_contact_attrs(contact_data, ref_data) do
    gender_name = get_in(contact_data, ["gender", "data", "name"])
    gender_id = if gender_name, do: Map.get(ref_data.genders, gender_name)

    birthdate_info = parse_special_date(get_in(contact_data, ["birthdate", "data"]))
    first_met_info = parse_special_date(get_in(contact_data, ["first_met_date", "data"]))

    is_active = contact_data["is_active"]
    is_archived = if is_active == false, do: true, else: false

    base = %{
      first_name: contact_data["first_name"],
      last_name: contact_data["last_name"],
      middle_name: contact_data["middle_name"],
      nickname: contact_data["nickname"],
      description: contact_data["description"],
      company: contact_data["company"],
      occupation: contact_data["job"],
      favorite: contact_data["is_starred"] || false,
      is_archived: is_archived,
      deceased: contact_data["is_dead"] || false,
      gender_id: gender_id
    }

    base
    |> maybe_put(:birthdate, birthdate_info[:date])
    |> maybe_put(:birthdate_year_unknown, birthdate_info[:year_unknown])
    |> maybe_put(:first_met_at, first_met_info[:date])
    |> maybe_put(:first_met_year_unknown, first_met_info[:year_unknown])
  end

  defp parse_special_date(nil), do: %{}

  defp parse_special_date(date_data) do
    date_str = date_data["date"]

    if date_str do
      case Date.from_iso8601(date_str) do
        {:ok, date} ->
          year_unknown = date_data["is_year_unknown"] == true
          %{date: date, year_unknown: year_unknown}

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ── Phase 3: Contact children ─────────────────────────────────────────

  defp import_contact_children(contact, user_id, contact_data, ref_data, import_record, acc) do
    notes_count = import_contact_fields(contact, contact_data, ref_data, import_record)
    import_addresses(contact, contact_data, import_record)
    n = import_notes(contact, user_id, contact_data, import_record)
    import_reminders(contact, user_id, contact_data, import_record)
    import_pets(contact, contact_data, import_record)
    import_photos(contact, contact_data, import_record)

    new_activity_set =
      import_activities(contact, user_id, contact_data, ref_data, import_record, acc.activity_set)

    # Import tags (join table)
    import_tags(contact, contact_data, ref_data)

    _ = notes_count

    %{acc | contacts: acc.contacts + 1, notes: acc.notes + n, activity_set: new_activity_set}
  end

  defp import_contact_fields(contact, contact_data, ref_data, import_record) do
    fields = get_in(contact_data, ["contact_fields", "data"]) || []

    Enum.each(fields, fn field_data ->
      cft_name = get_in(field_data, ["contact_field_type", "data", "name"])
      cft_id = Map.get(ref_data.contact_field_types, cft_name)

      attrs = %{
        "value" => field_data["content"],
        "contact_field_type_id" => cft_id
      }

      case Contacts.create_contact_field(contact, attrs) do
        {:ok, cf} ->
          maybe_record_entity(
            import_record,
            "contact_field",
            field_data["uuid"],
            "contact_field",
            cf.id
          )

        {:error, reason} ->
          Logger.warning(
            "[Monica Import] Contact field for #{contact.first_name}: #{inspect(reason)}"
          )
      end
    end)

    length(fields)
  end

  defp import_addresses(contact, contact_data, import_record) do
    addresses = get_in(contact_data, ["addresses", "data"]) || []

    Enum.each(addresses, fn addr_data ->
      attrs = %{
        "label" => addr_data["name"],
        "line1" => addr_data["street"],
        "city" => addr_data["city"],
        "province" => addr_data["province"],
        "postal_code" => addr_data["postal_code"],
        "country" => addr_data["country"]
      }

      case Contacts.create_address(contact, attrs) do
        {:ok, addr} ->
          maybe_record_entity(import_record, "address", addr_data["uuid"], "address", addr.id)

        {:error, reason} ->
          Logger.warning("[Monica Import] Address for #{contact.first_name}: #{inspect(reason)}")
      end
    end)
  end

  defp import_notes(contact, user_id, contact_data, import_record) do
    notes = get_in(contact_data, ["notes", "data"]) || []

    Enum.each(notes, fn note_data ->
      attrs = %{"body" => note_data["body"]}

      case Contacts.create_note(contact, user_id, attrs) do
        {:ok, note} ->
          maybe_record_entity(import_record, "note", note_data["uuid"], "note", note.id)

        {:error, reason} ->
          Logger.warning("[Monica Import] Note for #{contact.first_name}: #{inspect(reason)}")
      end
    end)

    length(notes)
  end

  defp import_reminders(contact, user_id, contact_data, import_record) do
    reminders = get_in(contact_data, ["reminders", "data"]) || []

    Enum.each(reminders, fn rem_data ->
      next_date = rem_data["next_expected_date"]

      attrs = %{
        type: "one_time",
        title: rem_data["title"],
        next_reminder_date: next_date,
        contact_id: contact.id
      }

      case Kith.Reminders.create_reminder(contact.account_id, user_id, attrs) do
        {:ok, reminder} ->
          maybe_record_entity(
            import_record,
            "reminder",
            rem_data["uuid"],
            "reminder",
            reminder.id
          )

        {:error, reason} ->
          Logger.warning("[Monica Import] Reminder for #{contact.first_name}: #{inspect(reason)}")
      end
    end)
  end

  defp import_pets(contact, contact_data, import_record) do
    pets = get_in(contact_data, ["pets", "data"]) || []

    Enum.each(pets, fn pet_data ->
      category_name = get_in(pet_data, ["pet_category", "data", "name"])
      species = map_pet_species(category_name)

      attrs = %{name: pet_data["name"], species: species, contact_id: contact.id}

      case Kith.Pets.create_pet(contact.account_id, attrs) do
        {:ok, pet} ->
          maybe_record_entity(import_record, "pet", pet_data["uuid"], "pet", pet.id)

        {:error, reason} ->
          Logger.warning("[Monica Import] Pet for #{contact.first_name}: #{inspect(reason)}")
      end
    end)
  end

  @pet_species_map %{
    "Dog" => "dog",
    "Cat" => "cat",
    "Bird" => "bird",
    "Fish" => "fish",
    "Reptile" => "reptile",
    "Rabbit" => "rabbit",
    "Hamster" => "hamster"
  }

  defp map_pet_species(nil), do: "other"
  defp map_pet_species(name), do: Map.get(@pet_species_map, name, "other")

  defp import_photos(contact, contact_data, import_record) do
    photos = get_in(contact_data, ["photos", "data"]) || []

    Enum.reduce(photos, contact, fn photo_data, current_contact ->
      file_name = photo_data["original_filename"] || "photo.jpg"

      {storage_key, file_size, content_hash} =
        resolve_photo_storage(current_contact, photo_data, file_name)

      if content_hash && Contacts.photo_exists_by_hash?(current_contact.id, content_hash) do
        Logger.debug(
          "[Monica Import] Skipping duplicate photo for #{current_contact.first_name}: #{content_hash}"
        )

        current_contact
      else
        attrs = %{
          "file_name" => file_name,
          "storage_key" => storage_key,
          "file_size" => file_size,
          "content_type" => photo_data["mime_type"] || "image/jpeg",
          "content_hash" => content_hash
        }

        case Contacts.create_photo(current_contact, attrs) do
          {:ok, photo} ->
            maybe_record_entity(import_record, "photo", photo_data["uuid"], "photo", photo.id)
            maybe_set_avatar(current_contact, photo, storage_key)

          {:error, reason} ->
            Logger.warning(
              "[Monica Import] Photo for #{current_contact.first_name}: #{inspect(reason)}"
            )

            current_contact
        end
      end
    end)
  end

  defp maybe_set_avatar(contact, _photo, "pending_sync:" <> _), do: contact

  defp maybe_set_avatar(contact, _photo, storage_key) do
    if is_nil(contact.avatar) do
      avatar_url = Kith.Storage.url(storage_key)
      contact |> Ecto.Changeset.change(avatar: avatar_url) |> Repo.update!()
    else
      contact
    end
  end

  defp resolve_photo_storage(contact, photo_data, file_name) do
    case decode_data_url(photo_data["dataUrl"]) do
      {:ok, binary} ->
        key = Kith.Storage.generate_key(contact.account_id, "photos", file_name)
        {:ok, _} = Kith.Storage.upload_binary(binary, key)
        content_hash = :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
        {key, byte_size(binary), content_hash}

      :error ->
        {"pending_sync:#{photo_data["uuid"]}", photo_data["filesize"] || 0, nil}
    end
  end

  defp decode_data_url("data:" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [_meta, encoded] -> {:ok, Base.decode64!(encoded)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp decode_data_url(_), do: :error

  defp import_activities(contact, user_id, contact_data, ref_data, import_record, activity_set) do
    activities = get_in(contact_data, ["activities", "data"]) || []

    Enum.reduce(activities, activity_set, fn activity_data, set ->
      uuid = activity_data["uuid"]

      cond do
        MapSet.member?(set, uuid) ->
          add_activity_contact_join(uuid, contact, import_record)
          set

        activity_already_imported?(import_record, contact, uuid) ->
          MapSet.put(set, uuid)

        true ->
          create_activity_with_contact(contact, user_id, activity_data, ref_data, import_record)
          MapSet.put(set, uuid)
      end
    end)
  end

  defp activity_already_imported?(import_record, contact, uuid) do
    existing_record =
      if import_record,
        do: Imports.find_import_record(contact.account_id, "monica", "activity", uuid)

    if existing_record do
      add_existing_activity_contact_join(existing_record.local_entity_id, contact)
      true
    else
      false
    end
  end

  defp add_activity_contact_join(activity_uuid, contact, _import_record) do
    # Find the local activity ID from import_records
    case Imports.find_import_record(contact.account_id, "monica", "activity", activity_uuid) do
      %{local_entity_id: activity_id} ->
        add_existing_activity_contact_join(activity_id, contact)

      nil ->
        Logger.warning("[Monica Import] Could not find activity #{activity_uuid} for join entry")
    end
  end

  defp add_existing_activity_contact_join(activity_id, contact) do
    Repo.insert_all(
      "activity_contacts",
      [%{activity_id: activity_id, contact_id: contact.id}],
      on_conflict: :nothing
    )
  end

  defp create_activity_with_contact(contact, user_id, activity_data, ref_data, import_record) do
    atc_name = get_in(activity_data, ["activity_type_category", "data", "name"])
    atc_id = if atc_name, do: Map.get(ref_data.activity_type_categories, atc_name)
    occurred_at = parse_activity_datetime(activity_data["happened_at"])

    attrs = %{
      title: activity_data["title"] || "Untitled Activity",
      description: activity_data["description"],
      occurred_at: occurred_at,
      activity_type_category_id: atc_id,
      creator_id: user_id
    }

    case Kith.Activities.create_activity(contact.account_id, attrs, [contact.id]) do
      {:ok, activity} ->
        maybe_record_entity(
          import_record,
          "activity",
          activity_data["uuid"],
          "activity",
          activity.id
        )

      {:error, reason} ->
        Logger.warning("[Monica Import] Activity for #{contact.first_name}: #{inspect(reason)}")
    end
  end

  defp import_tags(contact, contact_data, ref_data) do
    tags = get_in(contact_data, ["tags", "data"]) || []

    Enum.each(tags, fn tag_data ->
      tag_name = tag_data["name"]
      tag_id = Map.get(ref_data.tags, tag_name)

      if tag_id do
        Repo.insert_all(
          "contact_tags",
          [%{contact_id: contact.id, tag_id: tag_id}],
          on_conflict: :nothing
        )
      end
    end)
  end

  # ── Phase 4: Cross-contact references ─────────────────────────────────

  defp import_relationships(account_id, relationships_data, _ref_data, import_record) do
    Enum.reduce(relationships_data, [], fn rel_data, errors ->
      import_single_relationship(account_id, rel_data, import_record, errors)
    end)
  end

  defp import_single_relationship(account_id, rel_data, import_record, errors) do
    uuid = rel_data["uuid"]
    contact_is_uuid = rel_data["contact_is"]
    of_contact_uuid = rel_data["of_contact"]
    rt_name = get_in(rel_data, ["relationship_type", "data", "name"])
    rt_reverse = get_in(rel_data, ["relationship_type", "data", "reverse_name"])

    existing =
      if import_record && uuid,
        do: Imports.find_import_record(account_id, "monica", "relationship", uuid)

    if existing do
      maybe_record_entity(
        import_record,
        "relationship",
        uuid,
        "relationship",
        existing.local_entity_id
      )

      errors
    else
      create_new_relationship(
        account_id,
        import_record,
        uuid,
        contact_is_uuid,
        of_contact_uuid,
        rt_name,
        rt_reverse,
        errors
      )
    end
  end

  defp create_new_relationship(
         account_id,
         import_record,
         uuid,
         contact_is_uuid,
         of_contact_uuid,
         rt_name,
         rt_reverse,
         errors
       ) do
    with contact_is_rec when not is_nil(contact_is_rec) <-
           Imports.find_import_record(account_id, "monica", "contact", contact_is_uuid),
         of_contact_rec when not is_nil(of_contact_rec) <-
           Imports.find_import_record(account_id, "monica", "contact", of_contact_uuid),
         rt when not is_nil(rt) <-
           find_or_create_relationship_type(account_id, rt_name, rt_reverse) do
      rel_ctx = %{
        contact_is_rec: contact_is_rec,
        of_contact_rec: of_contact_rec,
        rt: rt,
        rt_name: rt_name,
        contact_is_uuid: contact_is_uuid,
        of_contact_uuid: of_contact_uuid
      }

      do_create_relationship(account_id, import_record, uuid, rel_ctx, errors)
    else
      nil ->
        msg =
          "Skipping relationship #{rt_name || "unknown"} between #{contact_is_uuid} and #{of_contact_uuid}: one or both contacts were not imported"

        Logger.warning("[Monica Import] #{msg}")
        errors ++ [msg]
    end
  end

  defp do_create_relationship(account_id, import_record, uuid, rel_ctx, errors) do
    contact = %Contacts.Contact{
      id: rel_ctx.contact_is_rec.local_entity_id,
      account_id: account_id
    }

    attrs = %{
      "related_contact_id" => rel_ctx.of_contact_rec.local_entity_id,
      "relationship_type_id" => rel_ctx.rt.id
    }

    case Contacts.create_relationship(contact, attrs) do
      {:ok, rel} ->
        maybe_record_entity(import_record, "relationship", uuid, "relationship", rel.id)
        errors

      {:error, reason} ->
        msg =
          "Relationship #{rel_ctx.rt_name} between #{rel_ctx.contact_is_uuid} and #{rel_ctx.of_contact_uuid}: #{inspect_errors(reason)}"

        Logger.warning("[Monica Import] #{msg}")
        errors ++ [msg]
    end
  rescue
    e in Ecto.ConstraintError ->
      Logger.info("[Monica Import] Relationship already exists: #{Exception.message(e)}")
      errors
  end

  defp find_or_create_relationship_type(_account_id, nil, _reverse), do: nil

  defp find_or_create_relationship_type(account_id, name, reverse_name) do
    Repo.one(
      from(rt in Contacts.RelationshipType,
        where: rt.name == ^name and (rt.account_id == ^account_id or is_nil(rt.account_id)),
        limit: 1
      )
    ) ||
      case Contacts.create_relationship_type(account_id, %{
             name: name,
             reverse_name: reverse_name || name
           }) do
        {:ok, rt} -> rt
        {:error, _} -> nil
      end
  end

  defp resolve_first_met_through(account_id, contacts_data, _import_record) do
    contacts_data
    |> Enum.filter(& &1["first_met_through"])
    |> Enum.reduce([], fn contact_data, errors ->
      resolve_single_first_met_through(account_id, contact_data, errors)
    end)
  end

  defp resolve_single_first_met_through(account_id, contact_data, errors) do
    uuid = contact_data["uuid"]
    through_uuid = contact_data["first_met_through"]

    with contact_rec when not is_nil(contact_rec) <-
           Imports.find_import_record(account_id, "monica", "contact", uuid),
         through_rec when not is_nil(through_rec) <-
           Imports.find_import_record(account_id, "monica", "contact", through_uuid),
         contact when not is_nil(contact) <-
           Repo.get(Contacts.Contact, contact_rec.local_entity_id),
         {:ok, _} <-
           Contacts.update_contact(contact, %{first_met_through_id: through_rec.local_entity_id}) do
      errors
    else
      nil ->
        msg = "Could not resolve first_met_through for #{uuid} -> #{through_uuid}"
        Logger.warning("[Monica Import] #{msg}")
        errors ++ [msg]

      {:error, reason} ->
        msg = "first_met_through for #{uuid}: #{inspect(reason)}"
        Logger.warning("[Monica Import] #{msg}")
        errors ++ [msg]
    end
  end

  # ── v4 format normalization ────────────────────────────────────────────
  #
  # Monica's JSON export comes in two flavours:
  #   v2  – the legacy API-style format with `contacts.data[]`
  #   v4  – the 1.0-preview export format with `account.data[]` sections
  #
  # We detect the format and normalize v4 → v2 so the rest of the import
  # pipeline can remain format-agnostic.

  defp normalize(%{"version" => "1.0" <> _rest, "account" => %{"data" => sections}} = parsed)
       when is_list(sections) do
    normalize_v4(parsed, sections)
  end

  defp normalize(parsed), do: parsed

  defp normalize_v4(parsed, sections) do
    raw_contacts = find_section_values(sections, "contact")
    raw_relationships = find_section_values(sections, "relationship")
    raw_photos = find_section_values(sections, "photo")
    raw_activities = find_section_values(sections, "activity")

    # Contact-level photos and activities are UUID references to top-level objects
    photo_lookup = Map.new(raw_photos, fn p -> {p["uuid"], p} end)
    activity_lookup = Map.new(raw_activities, fn a -> {a["uuid"], a} end)
    lookups = %{photos: photo_lookup, activities: activity_lookup}

    contacts = deduplicate_by_uuid(raw_contacts)
    transformed_contacts = Enum.map(contacts, &transform_v4_contact(&1, lookups))
    transformed_relationships = Enum.map(raw_relationships, &transform_v4_relationship/1)

    %{
      "contacts" => %{"data" => transformed_contacts},
      "relationships" => %{"data" => transformed_relationships},
      "account" => %{"data" => parsed["account"]},
      "version" => parsed["version"]
    }
  end

  defp find_section_values(sections, type) do
    case Enum.find(sections, &(&1["type"] == type)) do
      nil -> []
      section -> section["values"] || []
    end
  end

  defp deduplicate_by_uuid(entries) do
    entries
    |> Enum.group_by(& &1["uuid"])
    |> Enum.map(fn {_uuid, group} -> merge_contact_entries(group) end)
  end

  defp merge_contact_entries([single]), do: single

  defp merge_contact_entries(group) do
    primary = Enum.max_by(group, fn e -> e["updated_at"] || "" end)
    merged_data = merge_sub_data(group)
    Map.put(primary, "data", merged_data)
  end

  defp merge_sub_data(group) do
    group
    |> Enum.flat_map(fn entry -> entry["data"] || [] end)
    |> Enum.group_by(fn section -> section["type"] end)
    |> Enum.map(fn {type, sections} ->
      all_values =
        sections
        |> Enum.flat_map(fn section -> section["values"] || [] end)
        |> deduplicate_values()

      %{"type" => type, "count" => length(all_values), "values" => all_values}
    end)
  end

  defp deduplicate_values(values) do
    Enum.uniq_by(values, fn
      v when is_binary(v) -> v
      %{"uuid" => uuid} -> uuid
      other -> other
    end)
  end

  defp transform_v4_contact(v4, lookups) do
    props = v4["properties"] || %{}
    sub_data = v4["data"] || []

    gender_name = parse_gender_from_vcard(props["vcard"])
    tags = (props["tags"] || []) |> Enum.map(&%{"name" => &1})

    contact_fields = find_sub_values(sub_data, "contact_field")
    addresses = find_sub_values(sub_data, "address")
    notes = find_sub_values(sub_data, "note")
    reminders = find_sub_values(sub_data, "reminder")
    pets = find_sub_values(sub_data, "pet")

    # Contact-level photos/activities may be UUID strings referencing top-level objects
    photos = resolve_uuid_refs(find_sub_values(sub_data, "photo"), lookups.photos)
    activities = resolve_uuid_refs(find_sub_values(sub_data, "activity"), lookups.activities)

    %{
      "uuid" => v4["uuid"],
      "first_name" => props["first_name"],
      "last_name" => props["last_name"],
      "middle_name" => props["middle_name"],
      "nickname" => props["nickname"],
      "description" => props["description"],
      "company" => props["company"],
      "job" => props["occupation"],
      "is_starred" => props["is_starred"] || false,
      "is_active" => props["is_active"],
      "is_dead" => props["is_dead"] || false,
      "gender" => if(gender_name, do: %{"data" => %{"name" => gender_name}}),
      "birthdate" => %{"data" => parse_v4_birthdate(props)},
      "first_met_date" => %{"data" => parse_v4_first_met(props)},
      "first_met_through" => nil,
      "tags" => %{"data" => tags},
      "contact_fields" => %{"data" => Enum.map(contact_fields, &transform_v4_field/1)},
      "addresses" => %{"data" => Enum.map(addresses, &transform_v4_address/1)},
      "notes" => %{"data" => Enum.map(notes, &transform_v4_note/1)},
      "reminders" => %{"data" => Enum.map(reminders, &transform_v4_reminder/1)},
      "pets" => %{"data" => Enum.map(pets, &transform_v4_pet/1)},
      "photos" => %{"data" => Enum.map(photos, &transform_v4_photo/1)},
      "activities" => %{"data" => Enum.map(activities, &transform_v4_activity/1)}
    }
  end

  defp find_sub_values(sub_data, type) do
    case Enum.find(sub_data, &(&1["type"] == type)) do
      nil -> []
      section -> section["values"] || []
    end
  end

  defp resolve_uuid_refs(values, lookup) do
    Enum.flat_map(values, fn
      uuid when is_binary(uuid) ->
        case Map.get(lookup, uuid) do
          nil -> [%{"uuid" => uuid}]
          obj -> [obj]
        end

      %{} = obj ->
        [obj]

      _ ->
        []
    end)
  end

  defp parse_gender_from_vcard(nil), do: nil

  defp parse_gender_from_vcard(vcard) do
    case Regex.run(~r/GENDER:(\w)/, vcard) do
      [_, "M"] -> "Male"
      [_, "F"] -> "Female"
      [_, "O"] -> "Other"
      [_, "N"] -> "None"
      _ -> nil
    end
  end

  defp parse_v4_birthdate(%{"birthdate" => bd}) when is_binary(bd), do: %{"date" => bd}
  defp parse_v4_birthdate(_), do: nil

  defp parse_v4_first_met(%{"first_met_date" => d}) when is_binary(d), do: %{"date" => d}
  defp parse_v4_first_met(_), do: nil

  defp transform_v4_field(field) do
    props = field["properties"] || %{}
    value = props["data"]
    type_name = infer_field_type(value)

    %{
      "uuid" => field["uuid"],
      "content" => value,
      "contact_field_type" => %{"data" => %{"name" => type_name}}
    }
  end

  defp infer_field_type(nil), do: "Other"

  defp infer_field_type(value) do
    cond do
      String.contains?(value, "@") -> "Email"
      String.match?(value, ~r/^https?:\/\//) -> "Website"
      String.match?(value, ~r/^[\d\+\(\)\-\s\.]+$/) -> "Phone"
      true -> "Other"
    end
  end

  defp transform_v4_address(addr) do
    props = addr["properties"] || %{}

    %{
      "uuid" => addr["uuid"],
      "name" => props["name"],
      "street" => props["street"],
      "city" => props["city"],
      "province" => props["province"],
      "postal_code" => props["postal_code"],
      "country" => props["country"]
    }
  end

  defp transform_v4_note(note) do
    props = note["properties"] || %{}

    %{
      "uuid" => note["uuid"],
      "body" => props["body"],
      "created_at" => note["created_at"]
    }
  end

  defp transform_v4_reminder(reminder) do
    props = reminder["properties"] || %{}

    %{
      "uuid" => reminder["uuid"],
      "title" => props["title"],
      "next_expected_date" => props["initial_date"],
      "frequency_type" => props["frequency_type"]
    }
  end

  defp transform_v4_pet(pet) do
    props = pet["properties"] || %{}
    category = (props["category"] || "other") |> String.capitalize()

    %{
      "uuid" => pet["uuid"],
      "name" => props["name"],
      "pet_category" => %{"data" => %{"name" => category}}
    }
  end

  defp transform_v4_photo(photo) do
    props = photo["properties"] || %{}

    %{
      "uuid" => photo["uuid"],
      "original_filename" => props["original_filename"] || "photo.jpg",
      "filesize" => props["filesize"] || 0,
      "mime_type" => props["mime_type"] || "image/jpeg",
      "dataUrl" => props["dataUrl"]
    }
  end

  defp transform_v4_activity(activity) do
    props = activity["properties"] || %{}

    %{
      "uuid" => activity["uuid"],
      "title" => props["summary"] || props["title"],
      "description" => props["description"],
      "happened_at" => props["happened_at"]
    }
  end

  defp transform_v4_relationship(rel) do
    props = rel["properties"] || %{}
    type_name = (props["type"] || "friend") |> String.capitalize()

    %{
      "uuid" => rel["uuid"],
      "contact_is" => props["contact_is"],
      "of_contact" => props["of_contact"],
      "relationship_type" => %{
        "data" => %{
          "name" => type_name,
          "reverse_name" => type_name
        }
      }
    }
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp contact_display_name(contact_data) do
    [contact_data["first_name"], contact_data["last_name"]]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
  end

  defp add_error(acc, msg) do
    errors = if length(acc.errors) < 50, do: acc.errors ++ [msg], else: acc.errors
    %{acc | skipped: acc.skipped + 1, error_count: acc.error_count + 1, errors: errors}
  end

  defp inspect_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> inspect()
  end

  defp inspect_errors(other), do: inspect(other)

  defp maybe_record_entity(nil, _type, _uuid, _local_type, _local_id), do: :ok
  defp maybe_record_entity(_import_record, _type, nil, _local_type, _local_id), do: :ok

  defp maybe_record_entity(import_record, type, uuid, local_type, local_id) do
    Imports.record_imported_entity(import_record, type, uuid, local_type, local_id)
  end

  defp parse_activity_datetime(nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp parse_activity_datetime(dt_str) do
    case DateTime.from_iso8601(dt_str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end
end
