defmodule Kith.Imports.Sources.MonicaApi do
  @moduledoc """
  Monica CRM API-crawl import source.

  Imports contacts directly from a Monica instance via its REST API,
  eliminating the need for a JSON file export. Crawls the paginated
  contacts list endpoint and imports all embedded data in a single pass,
  then resolves cross-references (first_met_through, relationships) in
  a second pass once all contacts exist locally.

  ## Phases

    1. **Contact crawl** — paginate through `GET /api/contacts?limit=100&with=contactfields`,
       creating contacts with addresses, tags, contact fields, and up to 3 notes each.
    2. **Cross-references** — resolve `first_met_through_contact` and relationships
       using import_records (no API calls needed).
    3. **Extra notes** — for contacts with `statistics.number_of_notes > 3`,
       fetch remaining notes via `GET /api/contacts/{id}/notes`.
    4. **Photos** — optionally crawl `GET /api/photos?limit=100` to import all photos.
  """

  @behaviour Kith.Imports.Source

  import Ecto.Query, warn: false

  alias Kith.Contacts
  alias Kith.Imports
  alias Kith.Repo

  require Logger

  @page_limit 100
  @max_rate_limit_retries 3
  @rate_limit_sleep_ms :timer.seconds(65)

  # ── Behaviour callbacks ───────────────────────────────────────────────

  @impl true
  def name, do: "Monica CRM (API)"

  @impl true
  def file_types, do: []

  @impl true
  def supports_api?, do: true

  @impl true
  def validate_file(_data), do: {:error, "API import does not use files"}

  @impl true
  def parse_summary(_data), do: {:error, "API import does not use files"}

  @impl true
  def import(_account_id, _user_id, _data, _opts),
    do: {:error, "Use MonicaApiCrawlWorker for API imports"}

  @impl true
  def test_connection(%{url: url} = credential) do
    case api_get(credential, "#{url}/api/me") do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: 401}} -> {:error, "Invalid API key"}
      {:ok, %{status: status}} -> {:error, "Unexpected status: #{status}"}
      {:error, reason} -> {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  # ── Main crawl entry point ───────────────────────────────────────────

  @doc """
  Crawls a Monica instance via API and imports all contacts.

  Called by `MonicaApiCrawlWorker.perform/1`. Returns `{:ok, summary}` or `{:error, reason}`.
  """
  def crawl(account_id, user_id, credential, import_job, opts \\ %{}) do
    ctx = %{
      account_id: account_id,
      user_id: user_id,
      credential: credential,
      import_job: import_job,
      topic: "import:#{account_id}"
    }

    # Phase 1: Crawl contacts
    {acc, deferred} = crawl_all_contacts(ctx)

    # Phase 2: Resolve cross-references
    ref_errors = resolve_cross_references(account_id, deferred, import_job)

    # Phase 3: Extra notes
    notes_errors =
      if opts["extra_notes"] != false do
        fetch_all_extra_notes(credential, account_id, user_id, deferred.extra_notes, import_job)
      else
        []
      end

    # Phase 4: Photos (optional)
    photo_errors =
      if opts["photos"] do
        crawl_all_photos(credential, account_id, import_job)
      else
        []
      end

    all_errors = acc.errors ++ ref_errors ++ notes_errors ++ photo_errors

    error_count =
      acc.error_count + length(ref_errors) + length(notes_errors) + length(photo_errors)

    {:ok,
     %{
       imported: acc.contacts,
       contacts: acc.contacts,
       notes: acc.notes,
       skipped: acc.skipped,
       error_count: error_count,
       errors: Enum.take(all_errors, 50)
     }}
  catch
    :cancelled ->
      {:ok,
       %{
         imported: 0,
         contacts: 0,
         notes: 0,
         skipped: 0,
         error_count: 1,
         errors: ["Import cancelled"]
       }}
  end

  # ── Phase 1: Paginated contact crawl ──────────────────────────────────

  defp crawl_all_contacts(ctx) do
    initial_state = %{
      page: 1,
      total: nil,
      acc: %{contacts: 0, notes: 0, skipped: 0, error_count: 0, errors: []},
      deferred: %{first_met_through: [], relationships: [], extra_notes: []},
      ref_data: nil,
      global_idx: 0
    }

    crawl_contacts_loop(ctx, initial_state)
  end

  defp crawl_contacts_loop(ctx, state) do
    case fetch_contacts_page(ctx.credential, state.page) do
      {:ok, %{"data" => contacts, "meta" => meta}} when is_list(contacts) ->
        handle_contacts_page(ctx, state, contacts, meta)

      {:ok, %{"data" => [], "meta" => _}} ->
        {state.acc, state.deferred}

      {:ok, unexpected} ->
        Logger.error("[MonicaApi] Unexpected contacts response: #{inspect(unexpected)}")
        acc = add_error(state.acc, "Unexpected API response format from contacts endpoint")
        {acc, state.deferred}

      {:error, :rate_limited} ->
        acc = add_error(state.acc, "Rate limited by Monica API after retries")
        {acc, state.deferred}

      {:error, reason} ->
        acc =
          add_error(state.acc, "Failed to fetch contacts page #{state.page}: #{inspect(reason)}")

        {acc, state.deferred}
    end
  end

  defp handle_contacts_page(ctx, state, contacts, meta) do
    total = state.total || meta["total"] || 0
    last_page = meta["last_page"] || 1

    ref_data = build_or_update_ref_data(ctx.account_id, contacts, state.ref_data)

    {acc, deferred, global_idx} =
      process_contact_page(
        ctx,
        contacts,
        ref_data,
        total,
        state.acc,
        state.deferred,
        state.global_idx
      )

    if state.page < last_page do
      next_state = %{
        state
        | page: state.page + 1,
          total: total,
          acc: acc,
          deferred: deferred,
          ref_data: ref_data,
          global_idx: global_idx
      }

      crawl_contacts_loop(ctx, next_state)
    else
      {acc, deferred}
    end
  end

  defp fetch_contacts_page(credential, page) do
    url = "#{credential.url}/api/contacts"
    params = [limit: @page_limit, page: page, with: "contactfields"]
    api_get_json(credential, url, params)
  end

  defp process_contact_page(ctx, contacts, ref_data, total, acc, deferred, global_idx) do
    broadcast_interval = max(1, div(total, 50))

    Enum.reduce(contacts, {acc, deferred, global_idx}, fn api_contact,
                                                          {acc_inner, def_inner, idx} ->
      idx = idx + 1
      maybe_check_import_cancelled(ctx.import_job, idx)

      {acc_inner, def_inner} =
        safe_import_api_contact(ctx, api_contact, ref_data, acc_inner, def_inner)

      maybe_broadcast_progress(ctx.topic, idx, total, broadcast_interval)
      {acc_inner, def_inner, idx}
    end)
  end

  defp safe_import_api_contact(ctx, api_contact, ref_data, acc, deferred) do
    import_api_contact(ctx, api_contact, ref_data, acc, deferred)
  rescue
    e ->
      name = api_contact_display_name(api_contact)
      msg = "Contact #{name}: #{Exception.message(e)}"
      Logger.error("[MonicaApi] #{msg}")
      {add_error(acc, msg), deferred}
  end

  defp import_api_contact(ctx, api_contact, ref_data, acc, deferred) do
    source_id = to_string(api_contact["id"])

    # Check for existing import record (re-import)
    existing = Imports.find_import_record(ctx.account_id, "monica_api", "contact", source_id)

    case existing do
      %{local_entity_id: local_id} ->
        handle_existing_contact(ctx, api_contact, source_id, ref_data, acc, deferred, local_id)

      nil ->
        do_create_api_contact(ctx, api_contact, source_id, ref_data, acc, deferred)
    end
  end

  defp handle_existing_contact(ctx, api_contact, source_id, ref_data, acc, deferred, local_id) do
    case Repo.get(Contacts.Contact, local_id) do
      nil ->
        do_create_api_contact(ctx, api_contact, source_id, ref_data, acc, deferred)

      %{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        Logger.info("[MonicaApi] Skipping #{api_contact_display_name(api_contact)}: soft-deleted")

        {%{acc | skipped: acc.skipped + 1}, deferred}

      contact ->
        do_update_api_contact(ctx, contact, api_contact, source_id, ref_data, acc, deferred)
    end
  end

  defp do_create_api_contact(ctx, api_contact, source_id, ref_data, acc, deferred) do
    attrs = build_contact_attrs_from_api(api_contact, ref_data)

    case Contacts.create_contact(ctx.account_id, attrs) do
      {:ok, contact} ->
        Imports.record_imported_entity(
          ctx.import_job,
          "contact",
          source_id,
          "contact",
          contact.id
        )

        import_api_contact_children(ctx, contact, api_contact, source_id, ref_data, acc, deferred)

      {:error, changeset} ->
        name = api_contact_display_name(api_contact)
        msg = "Contact #{name}: #{inspect_errors(changeset)}"
        Logger.warning("[MonicaApi] #{msg}")
        {add_error(acc, msg), deferred}
    end
  end

  defp do_update_api_contact(ctx, contact, api_contact, source_id, ref_data, acc, deferred) do
    attrs = build_contact_attrs_from_api(api_contact, ref_data)

    case Contacts.update_contact(contact, attrs) do
      {:ok, contact} ->
        Imports.record_imported_entity(
          ctx.import_job,
          "contact",
          source_id,
          "contact",
          contact.id
        )

        import_api_contact_children(ctx, contact, api_contact, source_id, ref_data, acc, deferred)

      {:error, changeset} ->
        name = api_contact_display_name(api_contact)
        msg = "Contact #{name} (update): #{inspect_errors(changeset)}"
        Logger.warning("[MonicaApi] #{msg}")
        {add_error(acc, msg), deferred}
    end
  end

  # ── Contact attr mapping (API → Kith) ──────────────────────────────

  defp build_contact_attrs_from_api(api_contact, ref_data) do
    gender_name = api_contact["gender"]
    gender_id = if gender_name, do: Map.get(ref_data.genders, gender_name)

    info = api_contact["information"] || %{}
    career = info["career"] || %{}
    dates = info["dates"] || %{}
    how_you_met = info["how_you_met"] || %{}

    birthdate_info = parse_special_date(dates["birthdate"])
    first_met_date_info = parse_special_date(how_you_met["first_met_date"])

    is_active = api_contact["is_active"]
    is_archived = if is_active == false, do: true, else: false

    base = %{
      first_name: api_contact["first_name"],
      last_name: api_contact["last_name"],
      nickname: api_contact["nickname"],
      description: api_contact["description"],
      company: career["company"],
      occupation: career["job"],
      favorite: api_contact["is_starred"] || false,
      is_archived: is_archived,
      deceased: api_contact["is_dead"] || false,
      gender_id: gender_id
    }

    base
    |> maybe_put(:birthdate, birthdate_info[:date])
    |> maybe_put(:birthdate_year_unknown, birthdate_info[:year_unknown])
    |> maybe_put(:first_met_at, first_met_date_info[:date])
    |> maybe_put(:first_met_year_unknown, first_met_date_info[:year_unknown])
    |> maybe_put(:first_met_where, non_empty_string(how_you_met["first_met_where"]))
    |> maybe_put(:first_met_additional_info, non_empty_string(how_you_met["general_information"]))
  end

  # ── Contact children import ─────────────────────────────────────────

  defp import_api_contact_children(ctx, contact, api_contact, source_id, ref_data, acc, deferred) do
    # Contact fields (embedded with ?with=contactfields)
    import_api_contact_fields(contact, api_contact, ref_data, ctx.import_job)

    # Addresses (embedded directly)
    import_api_addresses(contact, api_contact, ctx.import_job)

    # Notes (up to 3 most recent, embedded with ?with=contactfields)
    n = import_api_notes(contact, ctx.user_id, api_contact, ctx.import_job)

    # Tags (embedded directly)
    import_api_tags(contact, api_contact, ref_data)

    # Collect deferred data
    deferred = collect_deferred_data(api_contact, source_id, deferred)

    acc = %{acc | contacts: acc.contacts + 1, notes: acc.notes + n}
    {acc, deferred}
  end

  defp import_api_contact_fields(contact, api_contact, ref_data, import_job) do
    fields = api_contact["contactFields"] || []

    Enum.each(fields, fn field ->
      import_single_contact_field(contact, field, ref_data, import_job)
    end)
  end

  defp import_single_contact_field(contact, field, ref_data, import_job) do
    cft_name = get_in(field, ["contact_field_type", "name"])
    cft_id = if cft_name, do: Map.get(ref_data.contact_field_types, cft_name)
    value = field["content"]

    if cft_id && value && !contact_field_duplicate?(contact.id, cft_id, value) do
      create_contact_field(contact, field, cft_id, value, import_job)
    end
  end

  defp create_contact_field(contact, field, cft_id, value, import_job) do
    attrs = %{"value" => value, "contact_field_type_id" => cft_id}

    case Contacts.create_contact_field(contact, attrs) do
      {:ok, cf} ->
        maybe_record_entity(import_job, "contact_field", field["uuid"], "contact_field", cf.id)

      {:error, reason} ->
        Logger.warning("[MonicaApi] Contact field for #{contact.first_name}: #{inspect(reason)}")
    end
  end

  defp import_api_addresses(contact, api_contact, import_job) do
    addresses = api_contact["addresses"] || []

    Enum.each(addresses, fn addr ->
      country_name =
        case addr["country"] do
          %{"name" => name} -> name
          name when is_binary(name) -> name
          _ -> nil
        end

      attrs = %{
        "label" => addr["name"],
        "line1" => addr["street"],
        "city" => addr["city"],
        "province" => addr["province"],
        "postal_code" => addr["postal_code"],
        "country" => country_name
      }

      case Contacts.create_address(contact, attrs) do
        {:ok, address} ->
          maybe_record_entity(import_job, "address", addr["uuid"], "address", address.id)

        {:error, reason} ->
          Logger.warning("[MonicaApi] Address for #{contact.first_name}: #{inspect(reason)}")
      end
    end)
  end

  defp import_api_notes(contact, user_id, api_contact, import_job) do
    notes = api_contact["notes"] || []

    Enum.each(notes, fn note ->
      attrs = %{"body" => note["body"]}

      case Contacts.create_note(contact, user_id, attrs) do
        {:ok, n} ->
          maybe_record_entity(import_job, "note", note["uuid"], "note", n.id)

        {:error, reason} ->
          Logger.warning("[MonicaApi] Note for #{contact.first_name}: #{inspect(reason)}")
      end
    end)

    length(notes)
  end

  defp import_api_tags(contact, api_contact, ref_data) do
    tags = api_contact["tags"] || []

    Enum.each(tags, fn tag ->
      tag_name = tag["name"]
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

  defp collect_deferred_data(api_contact, source_id, deferred) do
    deferred
    |> collect_first_met_through(api_contact, source_id)
    |> collect_relationships(api_contact, source_id)
    |> collect_extra_notes(api_contact, source_id)
  end

  defp collect_first_met_through(deferred, api_contact, source_id) do
    info = api_contact["information"] || %{}
    how_you_met = info["how_you_met"] || %{}

    case how_you_met["first_met_through_contact"] do
      %{"id" => through_id} when not is_nil(through_id) ->
        entry = %{contact_source_id: source_id, through_source_id: to_string(through_id)}
        %{deferred | first_met_through: [entry | deferred.first_met_through]}

      _ ->
        deferred
    end
  end

  defp collect_relationships(deferred, api_contact, source_id) do
    info = api_contact["information"] || %{}
    relationships = info["relationships"] || %{}

    rel_entries =
      Enum.flat_map(relationships, fn {category, %{"contacts" => contacts}} ->
        Enum.map(contacts || [], fn rel ->
          rel_info = rel["relationship"] || %{}
          related_contact = rel["contact"] || %{}

          %{
            contact_source_id: source_id,
            related_source_id: to_string(related_contact["id"]),
            type_name: rel_info["name"] || category,
            reverse_name: rel_info["name"] || category
          }
        end)
      end)

    %{deferred | relationships: deferred.relationships ++ rel_entries}
  end

  defp collect_extra_notes(deferred, api_contact, source_id) do
    stats = api_contact["statistics"] || %{}
    note_count = stats["number_of_notes"] || 0
    embedded_notes = length(api_contact["notes"] || [])

    if note_count > embedded_notes do
      entry = %{
        source_id: source_id,
        monica_id: api_contact["id"],
        embedded_count: embedded_notes
      }

      %{deferred | extra_notes: [entry | deferred.extra_notes]}
    else
      deferred
    end
  end

  # ── Phase 2: Cross-reference resolution ──────────────────────────────

  defp resolve_cross_references(account_id, deferred, import_job) do
    fmt_errors = resolve_first_met_through(account_id, deferred.first_met_through)
    rel_errors = resolve_relationships(account_id, deferred.relationships, import_job)
    fmt_errors ++ rel_errors
  end

  defp resolve_first_met_through(account_id, entries) do
    Enum.reduce(entries, [], fn %{contact_source_id: source_id, through_source_id: through_id},
                                errors ->
      with contact_rec when not is_nil(contact_rec) <-
             Imports.find_import_record(account_id, "monica_api", "contact", source_id),
           through_rec when not is_nil(through_rec) <-
             Imports.find_import_record(account_id, "monica_api", "contact", through_id),
           contact when not is_nil(contact) <-
             Repo.get(Contacts.Contact, contact_rec.local_entity_id),
           {:ok, _} <-
             Contacts.update_contact(contact, %{first_met_through_id: through_rec.local_entity_id}) do
        errors
      else
        nil ->
          msg = "Could not resolve first_met_through for contact #{source_id} -> #{through_id}"
          Logger.warning("[MonicaApi] #{msg}")
          errors ++ [msg]

        {:error, reason} ->
          msg = "first_met_through for #{source_id}: #{inspect_errors(reason)}"
          Logger.warning("[MonicaApi] #{msg}")
          errors ++ [msg]
      end
    end)
  end

  defp resolve_relationships(account_id, entries, import_job) do
    Enum.reduce(entries, [], fn entry, errors ->
      resolve_single_relationship(account_id, entry, import_job, errors)
    end)
  end

  defp resolve_single_relationship(account_id, entry, import_job, errors) do
    with contact_rec when not is_nil(contact_rec) <-
           Imports.find_import_record(
             account_id,
             "monica_api",
             "contact",
             entry.contact_source_id
           ),
         related_rec when not is_nil(related_rec) <-
           Imports.find_import_record(
             account_id,
             "monica_api",
             "contact",
             entry.related_source_id
           ),
         rt when not is_nil(rt) <-
           find_or_create_relationship_type(account_id, entry.type_name, entry.reverse_name) do
      contact = %Contacts.Contact{id: contact_rec.local_entity_id, account_id: account_id}

      attrs = %{
        "related_contact_id" => related_rec.local_entity_id,
        "relationship_type_id" => rt.id
      }

      case Contacts.create_relationship(contact, attrs) do
        {:ok, rel} ->
          maybe_record_entity(import_job, "relationship", nil, "relationship", rel.id)
          errors

        {:error, reason} ->
          msg =
            "Relationship #{entry.type_name} between #{entry.contact_source_id} and #{entry.related_source_id}: #{inspect_errors(reason)}"

          Logger.warning("[MonicaApi] #{msg}")
          errors ++ [msg]
      end
    else
      nil ->
        msg =
          "Skipping relationship #{entry.type_name} between #{entry.contact_source_id} and #{entry.related_source_id}: one or both contacts not imported"

        Logger.warning("[MonicaApi] #{msg}")
        errors ++ [msg]
    end
  rescue
    e in Ecto.ConstraintError ->
      Logger.info("[MonicaApi] Relationship already exists: #{Exception.message(e)}")
      errors
  end

  # ── Phase 3: Extra notes ─────────────────────────────────────────────

  defp fetch_all_extra_notes(credential, account_id, user_id, entries, import_job) do
    Enum.reduce(entries, [], fn entry, errors ->
      fetch_extra_notes_for_contact(credential, account_id, user_id, entry, import_job, errors)
    end)
  end

  defp fetch_extra_notes_for_contact(credential, account_id, user_id, entry, import_job, errors) do
    contact_rec =
      Imports.find_import_record(account_id, "monica_api", "contact", entry.source_id)

    if contact_rec do
      contact = Repo.get(Contacts.Contact, contact_rec.local_entity_id)

      if contact do
        fetch_notes_pages(credential, contact, user_id, entry, import_job, errors)
      else
        errors
      end
    else
      errors
    end
  end

  defp fetch_notes_pages(credential, contact, user_id, entry, import_job, errors) do
    fetch_notes_loop(
      credential,
      contact,
      user_id,
      entry,
      import_job,
      errors,
      _page = 1,
      _skip = entry.embedded_count
    )
  end

  defp fetch_notes_loop(credential, contact, user_id, entry, import_job, errors, page, skip) do
    url = "#{credential.url}/api/contacts/#{entry.monica_id}/notes"

    case api_get_json(credential, url, limit: @page_limit, page: page) do
      {:ok, %{"data" => notes, "meta" => meta}} when is_list(notes) ->
        last_page = meta["last_page"] || 1

        # Skip already-imported notes (first N were embedded in contact response)
        notes_to_import = if skip > 0, do: Enum.drop(notes, skip), else: notes
        import_extra_notes_batch(contact, user_id, notes_to_import, import_job)

        if page < last_page do
          fetch_notes_loop(credential, contact, user_id, entry, import_job, errors, page + 1, 0)
        else
          errors
        end

      {:error, :rate_limited} ->
        errors ++ ["Rate limited fetching notes for contact #{entry.source_id}"]

      {:error, reason} ->
        errors ++ ["Failed to fetch notes for contact #{entry.source_id}: #{inspect(reason)}"]

      _ ->
        errors
    end
  end

  defp import_extra_notes_batch(contact, user_id, notes, import_job) do
    Enum.each(notes, fn note ->
      attrs = %{"body" => note["body"]}

      case Contacts.create_note(contact, user_id, attrs) do
        {:ok, n} ->
          maybe_record_entity(import_job, "note", note["uuid"], "note", n.id)

        {:error, reason} ->
          Logger.warning("[MonicaApi] Extra note for #{contact.first_name}: #{inspect(reason)}")
      end
    end)
  end

  # ── Phase 4: Photo crawl ────────────────────────────────────────────

  defp crawl_all_photos(credential, account_id, import_job) do
    crawl_photos_loop(credential, account_id, import_job, _page = 1, _errors = [])
  end

  defp crawl_photos_loop(credential, account_id, import_job, page, errors) do
    url = "#{credential.url}/api/photos"

    case api_get_json(credential, url, limit: @page_limit, page: page) do
      {:ok, %{"data" => photos, "meta" => meta}} when is_list(photos) ->
        last_page = meta["last_page"] || 1

        errors =
          Enum.reduce(photos, errors, fn photo, errs ->
            import_api_photo(photo, account_id, import_job, errs)
          end)

        if page < last_page do
          crawl_photos_loop(credential, account_id, import_job, page + 1, errors)
        else
          errors
        end

      {:error, :rate_limited} ->
        errors ++ ["Rate limited fetching photos"]

      {:error, reason} ->
        errors ++ ["Failed to fetch photos page #{page}: #{inspect(reason)}"]

      _ ->
        errors
    end
  end

  defp import_api_photo(photo, account_id, import_job, errors) do
    contact_id = get_in(photo, ["contact", "id"])
    source_id = to_string(contact_id)

    contact_rec = Imports.find_import_record(account_id, "monica_api", "contact", source_id)

    if contact_rec do
      contact = Repo.get(Contacts.Contact, contact_rec.local_entity_id)

      if contact do
        do_import_photo(contact, photo, import_job, errors)
      else
        errors
      end
    else
      Logger.debug("[MonicaApi] Skipping photo for unknown contact #{source_id}")
      errors
    end
  end

  defp do_import_photo(contact, photo, import_job, errors) do
    file_name = photo["original_filename"] || "photo.jpg"

    case decode_photo_data(photo) do
      {:ok, binary} ->
        store_and_create_photo(contact, photo, binary, file_name, import_job, errors)

      :no_data ->
        errors

      :error ->
        errors ++ ["Failed to decode photo data for #{contact.first_name}"]
    end
  end

  defp store_and_create_photo(contact, photo, binary, file_name, import_job, errors) do
    content_hash = :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

    if Contacts.photo_exists_by_hash?(contact.id, content_hash) do
      Logger.debug("[MonicaApi] Skipping duplicate photo for #{contact.first_name}")
      errors
    else
      upload_and_record_photo(contact, photo, binary, file_name, content_hash, import_job, errors)
    end
  end

  defp upload_and_record_photo(
         contact,
         photo,
         binary,
         file_name,
         content_hash,
         import_job,
         errors
       ) do
    key = Kith.Storage.generate_key(contact.account_id, "photos", file_name)

    case Kith.Storage.upload_binary(binary, key) do
      {:ok, _} ->
        attrs = %{
          "file_name" => file_name,
          "storage_key" => key,
          "file_size" => byte_size(binary),
          "content_type" => photo["mime_type"] || "image/jpeg",
          "content_hash" => content_hash
        }

        create_photo_and_set_avatar(contact, photo, attrs, import_job, errors)

      {:error, reason} ->
        errors ++ ["Failed to store photo for #{contact.first_name}: #{inspect(reason)}"]
    end
  end

  defp create_photo_and_set_avatar(contact, photo, attrs, import_job, errors) do
    case Contacts.create_photo(contact, attrs) do
      {:ok, photo_record} ->
        maybe_record_entity(import_job, "photo", photo["uuid"], "photo", photo_record.id)

        if is_nil(contact.avatar) do
          contact |> Ecto.Changeset.change(avatar: attrs["storage_key"]) |> Repo.update!()
        end

        errors

      {:error, reason} ->
        Logger.warning("[MonicaApi] Photo for #{contact.first_name}: #{inspect(reason)}")
        errors
    end
  end

  defp decode_photo_data(%{"dataUrl" => "data:" <> _ = data_url}) do
    case String.split(data_url, ",", parts: 2) do
      [_meta, encoded] -> {:ok, Base.decode64!(encoded)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp decode_photo_data(%{"link" => link}) when is_binary(link) and link != "" do
    case Req.get(link, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      _ -> :error
    end
  end

  defp decode_photo_data(_), do: :no_data

  # ── Reference data building ──────────────────────────────────────────

  defp build_or_update_ref_data(account_id, contacts, nil) do
    genders = collect_api_genders(contacts)
    tags = collect_api_tags(contacts)
    cfts = collect_api_contact_field_types(contacts)

    %{
      genders: find_or_create_genders(account_id, genders),
      tags: find_or_create_tags(account_id, tags),
      contact_field_types: find_or_create_contact_field_types(account_id, cfts)
    }
  end

  defp build_or_update_ref_data(account_id, contacts, ref_data) do
    new_genders =
      contacts
      |> collect_api_genders()
      |> Enum.reject(&Map.has_key?(ref_data.genders, &1))

    new_tags =
      contacts
      |> collect_api_tags()
      |> Enum.reject(&Map.has_key?(ref_data.tags, &1))

    new_cfts =
      contacts
      |> collect_api_contact_field_types()
      |> Enum.reject(&Map.has_key?(ref_data.contact_field_types, &1))

    %{
      genders: Map.merge(ref_data.genders, find_or_create_genders(account_id, new_genders)),
      tags: Map.merge(ref_data.tags, find_or_create_tags(account_id, new_tags)),
      contact_field_types:
        Map.merge(
          ref_data.contact_field_types,
          find_or_create_contact_field_types(account_id, new_cfts)
        )
    }
  end

  defp collect_api_genders(contacts) do
    contacts
    |> Enum.map(& &1["gender"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp collect_api_tags(contacts) do
    contacts
    |> Enum.flat_map(fn c -> (c["tags"] || []) |> Enum.map(& &1["name"]) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp collect_api_contact_field_types(contacts) do
    contacts
    |> Enum.flat_map(fn c ->
      (c["contactFields"] || [])
      |> Enum.map(&get_in(&1, ["contact_field_type", "name"]))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp find_or_create_genders(_account_id, []), do: %{}

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

  defp find_or_create_tags(_account_id, []), do: %{}

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

  defp find_or_create_contact_field_types(_account_id, []), do: %{}

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

  # ── HTTP helpers ─────────────────────────────────────────────────────

  defp api_get(credential, url, params \\ []) do
    headers = [{"Authorization", "Bearer #{credential.api_key}"}, {"Accept", "application/json"}]
    req_options = Map.get(credential, :req_options, [])
    options = [headers: headers, params: params] ++ req_options

    Req.get(url, options)
  end

  defp api_get_json(credential, url, params) do
    api_get_json_with_retry(credential, url, params, 0)
  end

  defp api_get_json_with_retry(_credential, _url, _params, retries)
       when retries >= @max_rate_limit_retries do
    {:error, :rate_limited}
  end

  defp api_get_json_with_retry(credential, url, params, retries) do
    case api_get(credential, url, params) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 429}} ->
        Logger.info(
          "[MonicaApi] Rate limited, sleeping #{@rate_limit_sleep_ms}ms (retry #{retries + 1})"
        )

        Process.sleep(@rate_limit_sleep_ms)
        api_get_json_with_retry(credential, url, params, retries + 1)

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Date parsing helpers ─────────────────────────────────────────────

  defp parse_special_date(nil), do: %{}

  defp parse_special_date(date_data) do
    date_str = date_data["date"]

    if date_str do
      case parse_date_or_datetime(date_str) do
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

  defp parse_date_or_datetime(str) do
    case Date.from_iso8601(str) do
      {:ok, _date} = ok ->
        ok

      {:error, _} ->
        case DateTime.from_iso8601(str) do
          {:ok, dt, _offset} -> {:ok, DateTime.to_date(dt)}
          _ -> :error
        end
    end
  end

  # ── General helpers ──────────────────────────────────────────────────

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp non_empty_string(nil), do: nil
  defp non_empty_string(""), do: nil
  defp non_empty_string(s) when is_binary(s), do: s
  defp non_empty_string(_), do: nil

  defp add_error(acc, msg) do
    errors = if length(acc.errors) < 50, do: acc.errors ++ [msg], else: acc.errors
    %{acc | skipped: acc.skipped + 1, error_count: acc.error_count + 1, errors: errors}
  end

  defp api_contact_display_name(api_contact) do
    [api_contact["first_name"], api_contact["last_name"]]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
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

  defp maybe_record_entity(nil, _type, _id, _local_type, _local_id), do: :ok
  defp maybe_record_entity(_import, _type, nil, _local_type, _local_id), do: :ok

  defp maybe_record_entity(import_job, type, source_id, local_type, local_id) do
    Imports.record_imported_entity(import_job, type, to_string(source_id), local_type, local_id)
  end

  defp contact_field_duplicate?(_contact_id, nil, _value), do: false
  defp contact_field_duplicate?(_contact_id, _cft_id, nil), do: false

  defp contact_field_duplicate?(contact_id, cft_id, value) do
    Repo.exists?(
      from(cf in Contacts.ContactField,
        where:
          cf.contact_id == ^contact_id and
            cf.contact_field_type_id == ^cft_id and
            fragment("lower(?)", cf.value) == fragment("lower(?)", ^value)
      )
    )
  end

  defp maybe_check_import_cancelled(import_job, idx) do
    if import_job && rem(idx, 10) == 0 do
      refreshed = Imports.get_import!(import_job.id)
      if refreshed.status == "cancelled", do: throw(:cancelled)
    end
  end

  defp maybe_broadcast_progress(topic, idx, total, broadcast_interval) do
    if rem(idx, broadcast_interval) == 0 || idx == total do
      Phoenix.PubSub.broadcast(
        Kith.PubSub,
        topic,
        {:import_progress, %{current: idx, total: total}}
      )
    end
  end
end
