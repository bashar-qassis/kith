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
  alias Kith.Workers.MonicaDocumentImportWorker

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

    # Phase 1.5: Auto-merge definite duplicates (optional)
    merge_result =
      if opts["auto_merge_duplicates"] do
        auto_merge_duplicates(account_id, import_job)
      else
        %{merged: 0, errors: []}
      end

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

    # Phase 5-12: Additional data types (per-contact endpoints)
    extra_data_errors =
      import_extra_data_types(credential, account_id, user_id, import_job, opts)

    # Phase 13: Enqueue document import jobs (async, runs after main import)
    if opts["documents"] do
      enqueue_document_imports(credential, account_id, user_id, import_job)
    end

    all_errors =
      acc.errors ++
        ref_errors ++
        notes_errors ++
        photo_errors ++
        merge_result.errors ++
        extra_data_errors

    error_count =
      acc.error_count + length(ref_errors) + length(notes_errors) + length(photo_errors) +
        length(merge_result.errors) + length(extra_data_errors)

    {:ok,
     %{
       imported: acc.contacts,
       contacts: acc.contacts,
       notes: acc.notes,
       skipped: acc.skipped,
       merged: merge_result.merged,
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
         merged: 0,
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

      unless address_duplicate?(contact.id, attrs["line1"], attrs["city"], country_name) do
        create_imported_address(contact, attrs, addr, import_job)
      end
    end)
  end

  defp create_imported_address(contact, attrs, addr, import_job) do
    case Contacts.create_address(contact, attrs) do
      {:ok, address} ->
        maybe_record_entity(import_job, "address", addr["uuid"], "address", address.id)

      {:error, reason} ->
        Logger.warning("[MonicaApi] Address for #{contact.first_name}: #{inspect(reason)}")
    end
  end

  defp import_api_notes(contact, user_id, api_contact, import_job) do
    notes = api_contact["notes"] || []

    Enum.each(notes, fn note ->
      unless note_duplicate?(contact.id, note["body"]) do
        create_imported_note(contact, user_id, note, import_job)
      end
    end)

    length(notes)
  end

  defp create_imported_note(contact, user_id, note, import_job) do
    attrs = %{"body" => note["body"]}

    case Contacts.create_note(contact, user_id, attrs) do
      {:ok, n} ->
        maybe_record_entity(import_job, "note", note["uuid"], "note", n.id)

      {:error, reason} ->
        Logger.warning("[MonicaApi] Note for #{contact.first_name}: #{inspect(reason)}")
    end
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

  # ── Phase 1.5: Auto-merge definite duplicates ───────────────────────

  defp auto_merge_duplicates(account_id, import_job) do
    # Get all contact IDs imported in this batch
    import_records =
      Repo.all(
        from(ir in Imports.ImportRecord,
          where:
            ir.import_id == ^import_job.id and
              ir.source_entity_type == "contact",
          select: ir.local_entity_id
        )
      )

    # Load contacts with contact fields
    contacts =
      Repo.all(
        from(c in Contacts.Contact,
          where: c.id in ^import_records and is_nil(c.deleted_at),
          preload: [contact_fields: :contact_field_type]
        )
      )

    # Group by normalized name
    name_groups =
      contacts
      |> Enum.group_by(fn c ->
        {String.downcase(c.first_name || ""), String.downcase(c.last_name || "")}
      end)
      |> Enum.filter(fn {_key, group} -> length(group) >= 2 end)

    merged_ids = MapSet.new()
    {merged_count, errors, _} = merge_name_groups(name_groups, account_id, import_job, merged_ids)

    Logger.info("[MonicaApi] Auto-merge: #{merged_count} contacts merged")
    %{merged: merged_count, errors: errors}
  end

  defp merge_name_groups(groups, account_id, import_job, merged_ids) do
    Enum.reduce(groups, {0, [], merged_ids}, fn {_name_key, group}, {count, errors, seen} ->
      # Sort by ID so survivor is always the first-imported
      sorted = Enum.sort_by(group, & &1.id)
      merge_group_contacts(sorted, account_id, import_job, count, errors, seen)
    end)
  end

  defp merge_group_contacts([_single], _account_id, _import_job, count, errors, seen),
    do: {count, errors, seen}

  defp merge_group_contacts(
         [survivor | rest],
         account_id,
         import_job,
         count,
         errors,
         seen
       ) do
    if MapSet.member?(seen, survivor.id) do
      {count, errors, seen}
    else
      Enum.reduce(rest, {count, errors, seen}, fn candidate, acc ->
        try_merge_candidate(survivor, candidate, account_id, import_job, acc)
      end)
    end
  end

  defp try_merge_candidate(survivor, candidate, account_id, import_job, {c, e, s}) do
    cond do
      MapSet.member?(s, candidate.id) ->
        {c, e, s}

      not definite_duplicate?(survivor, candidate) ->
        {c, e, s}

      true ->
        case Contacts.merge_contacts(survivor.id, candidate.id) do
          {:ok, _} ->
            update_import_records_after_merge(account_id, import_job, candidate.id, survivor.id)
            {c + 1, e, MapSet.put(s, candidate.id)}

          {:error, reason} ->
            msg =
              "Failed to merge #{candidate.first_name} #{candidate.last_name} (#{candidate.id}): #{inspect(reason)}"

            Logger.warning("[MonicaApi] #{msg}")
            {c, e ++ [msg], s}
        end
    end
  end

  defp definite_duplicate?(contact_a, contact_b) do
    emails_a = extract_values_by_protocol(contact_a, "mailto")
    emails_b = extract_values_by_protocol(contact_b, "mailto")

    phones_a = extract_values_by_protocol(contact_a, "tel")
    phones_b = extract_values_by_protocol(contact_b, "tel")

    shared_email? = not MapSet.disjoint?(emails_a, emails_b)
    shared_phone? = not MapSet.disjoint?(phones_a, phones_b)

    shared_email? or shared_phone?
  end

  defp extract_values_by_protocol(contact, protocol_prefix) do
    contact.contact_fields
    |> Enum.filter(fn cf ->
      cf.contact_field_type &&
        String.starts_with?(cf.contact_field_type.protocol || "", protocol_prefix)
    end)
    |> Enum.map(fn cf -> String.downcase(cf.value || "") end)
    |> MapSet.new()
  end

  defp update_import_records_after_merge(account_id, import_job, old_contact_id, new_contact_id) do
    from(ir in Imports.ImportRecord,
      where:
        ir.import_id == ^import_job.id and
          ir.source_entity_type == "contact" and
          ir.local_entity_id == ^old_contact_id
    )
    |> Repo.update_all(set: [local_entity_id: new_contact_id])

    # Also update any non-contact records that reference the old contact
    # (This is handled by merge_contacts which remaps sub-entities,
    # but import_records still need updating for Phase 2 cross-refs)
    Logger.info(
      "[MonicaApi] Remapped import records from contact #{old_contact_id} to #{new_contact_id} " <>
        "(account #{account_id})"
    )
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
      unless note_duplicate?(contact.id, note["body"]) do
        create_imported_note(contact, user_id, note, import_job)
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

  defp address_duplicate?(contact_id, line1, city, country) do
    Repo.exists?(
      from(a in Contacts.Address,
        where:
          a.contact_id == ^contact_id and
            fragment("lower(coalesce(?, ''))", a.line1) ==
              fragment("lower(coalesce(?, ''))", ^(line1 || "")) and
            fragment("lower(coalesce(?, ''))", a.city) ==
              fragment("lower(coalesce(?, ''))", ^(city || "")) and
            fragment("lower(coalesce(?, ''))", a.country) ==
              fragment("lower(coalesce(?, ''))", ^(country || ""))
      )
    )
  end

  defp note_duplicate?(_contact_id, nil), do: false
  defp note_duplicate?(_contact_id, ""), do: false

  defp note_duplicate?(contact_id, body) when is_binary(body) do
    trimmed = String.trim(body)

    Repo.exists?(
      from(n in Contacts.Note,
        where:
          n.contact_id == ^contact_id and
            fragment("trim(?)", n.body) == ^trimmed
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

  # ── Phases 5-12: Additional per-contact data types ─────────────────

  defp import_extra_data_types(credential, account_id, user_id, import_job, opts) do
    # Get all imported contact IDs for this job
    contact_records =
      Repo.all(
        from(ir in Imports.ImportRecord,
          where:
            ir.import_id == ^import_job.id and
              ir.source_entity_type == "contact",
          select: {ir.source_entity_id, ir.local_entity_id}
        )
      )

    errors =
      Enum.flat_map(contact_records, fn {source_id, local_id} ->
        contact =
          Repo.get(Contacts.Contact, local_id)

        if contact && is_nil(contact.deleted_at) do
          import_per_contact_data(
            credential,
            account_id,
            user_id,
            contact,
            source_id,
            import_job,
            opts
          )
        else
          []
        end
      end)

    errors
  end

  defp import_per_contact_data(
         credential,
         account_id,
         user_id,
         contact,
         source_id,
         import_job,
         opts
       ) do
    errors = []
    base_url = credential.url

    # Phase 5: Pets
    errors =
      if opts["pets"] do
        errors ++
          import_contact_pets(credential, base_url, account_id, contact, source_id, import_job)
      else
        errors
      end

    # Phase 6: Calls
    errors =
      if opts["calls"] do
        errors ++
          import_contact_calls(
            credential,
            base_url,
            account_id,
            user_id,
            contact,
            source_id,
            import_job
          )
      else
        errors
      end

    # Phase 7: Activities
    errors =
      if opts["activities"] do
        errors ++
          import_contact_activities(
            credential,
            base_url,
            account_id,
            user_id,
            contact,
            source_id,
            import_job
          )
      else
        errors
      end

    # Phase 8: Gifts
    errors =
      if opts["gifts"] do
        errors ++
          import_contact_gifts(
            credential,
            base_url,
            account_id,
            user_id,
            contact,
            source_id,
            import_job
          )
      else
        errors
      end

    # Phase 9: Debts
    errors =
      if opts["debts"] do
        errors ++
          import_contact_debts(
            credential,
            base_url,
            account_id,
            user_id,
            contact,
            source_id,
            import_job
          )
      else
        errors
      end

    # Phase 10: Tasks
    errors =
      if opts["tasks"] do
        errors ++
          import_contact_tasks(
            credential,
            base_url,
            account_id,
            user_id,
            contact,
            source_id,
            import_job
          )
      else
        errors
      end

    # Phase 11: Reminders
    errors =
      if opts["reminders"] do
        errors ++
          import_contact_reminders(
            credential,
            base_url,
            account_id,
            user_id,
            contact,
            source_id,
            import_job
          )
      else
        errors
      end

    # Phase 12: Conversations
    errors =
      if opts["conversations"] do
        errors ++
          import_contact_conversations(
            credential,
            base_url,
            account_id,
            user_id,
            contact,
            source_id,
            import_job
          )
      else
        errors
      end

    errors
  end

  # ── Phase 5: Pets ──────────────────────────────────────────────────

  defp import_contact_pets(credential, base_url, account_id, contact, source_id, import_job) do
    url = "#{base_url}/api/contacts/#{source_id}/pets"

    case api_get_json(credential, url, []) do
      {:ok, %{"data" => pets}} when is_list(pets) ->
        Enum.flat_map(pets, fn pet ->
          import_single_pet(account_id, contact, pet, import_job)
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        ["Failed to fetch pets for contact #{source_id}: #{inspect(reason)}"]
    end
  end

  defp import_single_pet(account_id, contact, pet_data, import_job) do
    name = pet_data["name"]
    species = normalize_pet_species(pet_data["pet_category"] || pet_data["species"])

    if pet_duplicate?(contact.id, name, species) do
      []
    else
      attrs = %{
        "contact_id" => contact.id,
        "name" => name || "Unknown",
        "species" => species,
        "breed" => non_empty_string(pet_data["breed"]),
        "notes" => non_empty_string(pet_data["notes"])
      }

      case Kith.Pets.create_pet(account_id, attrs) do
        {:ok, pet} ->
          maybe_record_entity(import_job, "pet", pet_data["id"], "pet", pet.id)
          []

        {:error, reason} ->
          ["Pet import error: #{inspect_errors(reason)}"]
      end
    end
  end

  defp normalize_pet_species(nil), do: "other"

  defp normalize_pet_species(species) when is_map(species) do
    normalize_pet_species(species["name"])
  end

  defp normalize_pet_species(species) when is_binary(species) do
    normalized = String.downcase(species)

    if normalized in ~w(dog cat bird fish reptile rabbit hamster) do
      normalized
    else
      "other"
    end
  end

  defp normalize_pet_species(_), do: "other"

  defp pet_duplicate?(contact_id, name, species) do
    Repo.exists?(
      from(p in Kith.Contacts.Pet,
        where:
          p.contact_id == ^contact_id and
            fragment("lower(coalesce(?, ''))", p.name) ==
              fragment("lower(coalesce(?, ''))", ^(name || "")) and
            p.species == ^species
      )
    )
  end

  # ── Phase 6: Calls ─────────────────────────────────────────────────

  defp import_contact_calls(
         credential,
         base_url,
         account_id,
         _user_id,
         contact,
         source_id,
         import_job
       ) do
    url = "#{base_url}/api/contacts/#{source_id}/calls"

    case api_get_json(credential, url, []) do
      {:ok, %{"data" => calls}} when is_list(calls) ->
        Enum.flat_map(calls, fn call ->
          import_single_call(account_id, contact, call, import_job)
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        ["Failed to fetch calls for contact #{source_id}: #{inspect(reason)}"]
    end
  end

  defp import_single_call(account_id, contact, call_data, import_job) do
    occurred_at = parse_datetime(call_data["called_at"])

    if is_nil(occurred_at) do
      []
    else
      attrs = %{
        "occurred_at" => occurred_at,
        "notes" => non_empty_string(call_data["content"]),
        "duration_mins" => call_data["duration"]
      }

      case Kith.Activities.create_call(
             %{account_id: account_id, id: contact.id},
             attrs
           ) do
        {:ok, call} ->
          maybe_record_entity(import_job, "call", call_data["id"], "call", call.id)
          []

        {:error, reason} ->
          ["Call import error: #{inspect_errors(reason)}"]
      end
    end
  end

  # ── Phase 7: Activities ────────────────────────────────────────────

  defp import_contact_activities(
         credential,
         base_url,
         account_id,
         _user_id,
         contact,
         source_id,
         import_job
       ) do
    url = "#{base_url}/api/contacts/#{source_id}/activities"

    case api_get_json(credential, url, []) do
      {:ok, %{"data" => activities}} when is_list(activities) ->
        Enum.flat_map(activities, fn activity ->
          import_single_activity(account_id, contact, activity, import_job)
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        ["Failed to fetch activities for contact #{source_id}: #{inspect(reason)}"]
    end
  end

  defp import_single_activity(account_id, contact, activity_data, import_job) do
    occurred_at =
      parse_datetime(activity_data["happened_at"] || activity_data["date_it_happened"])

    attrs = %{
      "title" => activity_data["summary"] || activity_data["title"] || "Imported activity",
      "description" => non_empty_string(activity_data["description"]),
      "occurred_at" => occurred_at || DateTime.utc_now()
    }

    case Kith.Activities.create_activity(account_id, attrs, [contact.id]) do
      {:ok, activity} ->
        maybe_record_entity(
          import_job,
          "activity",
          activity_data["id"],
          "activity",
          activity.id
        )

        []

      {:error, reason} ->
        ["Activity import error: #{inspect_errors(reason)}"]
    end
  end

  # ── Phase 8: Gifts ─────────────────────────────────────────────────

  defp import_contact_gifts(
         credential,
         base_url,
         account_id,
         user_id,
         contact,
         source_id,
         import_job
       ) do
    url = "#{base_url}/api/contacts/#{source_id}/gifts"

    case api_get_json(credential, url, []) do
      {:ok, %{"data" => gifts}} when is_list(gifts) ->
        Enum.flat_map(gifts, fn gift ->
          import_single_gift(account_id, user_id, contact, gift, import_job)
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        ["Failed to fetch gifts for contact #{source_id}: #{inspect(reason)}"]
    end
  end

  defp import_single_gift(account_id, user_id, contact, gift_data, import_job) do
    direction =
      case gift_data["is_for"] do
        "contact" -> "given"
        _ -> "received"
      end

    attrs = %{
      "contact_id" => contact.id,
      "name" => gift_data["name"] || "Imported gift",
      "description" => non_empty_string(gift_data["comment"]),
      "direction" => direction,
      "status" =>
        cond do
          gift_data["has_been_offered"] -> "given"
          gift_data["has_been_received"] -> "received"
          true -> "idea"
        end,
      "amount" => gift_data["amount"],
      "date" => parse_date_string(gift_data["date"])
    }

    case Kith.Gifts.create_gift(account_id, user_id, attrs) do
      {:ok, gift} ->
        maybe_record_entity(import_job, "gift", gift_data["id"], "gift", gift.id)
        []

      {:error, reason} ->
        ["Gift import error: #{inspect_errors(reason)}"]
    end
  end

  # ── Phase 9: Debts ─────────────────────────────────────────────────

  defp import_contact_debts(
         credential,
         base_url,
         account_id,
         user_id,
         contact,
         source_id,
         import_job
       ) do
    url = "#{base_url}/api/contacts/#{source_id}/debts"

    case api_get_json(credential, url, []) do
      {:ok, %{"data" => debts}} when is_list(debts) ->
        Enum.flat_map(debts, fn debt ->
          import_single_debt(account_id, user_id, contact, debt, import_job)
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        ["Failed to fetch debts for contact #{source_id}: #{inspect(reason)}"]
    end
  end

  defp import_single_debt(account_id, user_id, contact, debt_data, import_job) do
    direction =
      case debt_data["in_debt"] do
        "yes" -> "owed_by_me"
        _ -> "owed_to_me"
      end

    attrs = %{
      "contact_id" => contact.id,
      "title" => debt_data["reason"] || "Imported debt",
      "amount" => debt_data["amount"] || "0",
      "direction" => direction,
      "status" => if(debt_data["status"] == "complete", do: "settled", else: "active")
    }

    case Kith.Debts.create_debt(account_id, user_id, attrs) do
      {:ok, debt} ->
        maybe_record_entity(import_job, "debt", debt_data["id"], "debt", debt.id)
        []

      {:error, reason} ->
        ["Debt import error: #{inspect_errors(reason)}"]
    end
  end

  # ── Phase 10: Tasks ────────────────────────────────────────────────

  defp import_contact_tasks(
         credential,
         base_url,
         account_id,
         user_id,
         contact,
         source_id,
         import_job
       ) do
    url = "#{base_url}/api/contacts/#{source_id}/tasks"

    case api_get_json(credential, url, []) do
      {:ok, %{"data" => tasks}} when is_list(tasks) ->
        Enum.flat_map(tasks, fn task ->
          import_single_task(account_id, user_id, contact, task, import_job)
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        ["Failed to fetch tasks for contact #{source_id}: #{inspect(reason)}"]
    end
  end

  defp import_single_task(account_id, user_id, contact, task_data, import_job) do
    status = if task_data["completed"], do: "completed", else: "pending"

    attrs = %{
      "contact_id" => contact.id,
      "title" => task_data["title"] || "Imported task",
      "description" => non_empty_string(task_data["description"]),
      "status" => status
    }

    case Kith.Tasks.create_task(account_id, user_id, attrs) do
      {:ok, task} ->
        maybe_record_entity(import_job, "task", task_data["id"], "task", task.id)
        []

      {:error, reason} ->
        ["Task import error: #{inspect_errors(reason)}"]
    end
  end

  # ── Phase 11: Reminders ────────────────────────────────────────────

  defp import_contact_reminders(
         credential,
         base_url,
         account_id,
         user_id,
         contact,
         source_id,
         import_job
       ) do
    url = "#{base_url}/api/contacts/#{source_id}/reminders"

    case api_get_json(credential, url, []) do
      {:ok, %{"data" => reminders}} when is_list(reminders) ->
        Enum.flat_map(reminders, fn reminder ->
          import_single_reminder(account_id, user_id, contact, reminder, import_job)
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        ["Failed to fetch reminders for contact #{source_id}: #{inspect(reason)}"]
    end
  end

  defp import_single_reminder(account_id, user_id, contact, reminder_data, import_job) do
    {type, frequency} = map_monica_reminder_frequency(reminder_data["frequency_type"])

    next_date =
      parse_date_string(reminder_data["next_expected_date"]) ||
        Date.utc_today()

    attrs = %{
      "contact_id" => contact.id,
      "type" => type,
      "title" => reminder_data["title"] || "Imported reminder",
      "frequency" => frequency,
      "next_reminder_date" => next_date
    }

    case Kith.Reminders.create_reminder(account_id, user_id, attrs) do
      {:ok, reminder} ->
        maybe_record_entity(
          import_job,
          "reminder",
          reminder_data["id"],
          "reminder",
          reminder.id
        )

        []

      {:error, reason} ->
        ["Reminder import error: #{inspect_errors(reason)}"]
    end
  end

  defp map_monica_reminder_frequency("one_time"), do: {"one_time", nil}
  defp map_monica_reminder_frequency("week"), do: {"recurring", "weekly"}
  defp map_monica_reminder_frequency("month"), do: {"recurring", "monthly"}
  defp map_monica_reminder_frequency("year"), do: {"recurring", "annually"}
  defp map_monica_reminder_frequency(_), do: {"one_time", nil}

  # ── Phase 12: Conversations ────────────────────────────────────────

  defp import_contact_conversations(
         credential,
         base_url,
         account_id,
         user_id,
         contact,
         source_id,
         import_job
       ) do
    url = "#{base_url}/api/contacts/#{source_id}/conversations"

    case api_get_json(credential, url, []) do
      {:ok, %{"data" => convos}} when is_list(convos) ->
        Enum.flat_map(convos, fn convo ->
          import_single_conversation(
            credential,
            base_url,
            account_id,
            user_id,
            contact,
            convo,
            import_job
          )
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        ["Failed to fetch conversations for contact #{source_id}: #{inspect(reason)}"]
    end
  end

  defp import_single_conversation(
         credential,
         base_url,
         account_id,
         user_id,
         contact,
         convo_data,
         import_job
       ) do
    platform =
      case convo_data["contact_field_type"] do
        %{"name" => name} -> normalize_conversation_platform(name)
        _ -> "other"
      end

    attrs = %{
      "contact_id" => contact.id,
      "platform" => platform,
      "subject" => non_empty_string(convo_data["subject"])
    }

    case Kith.Conversations.create_conversation(account_id, user_id, attrs) do
      {:ok, conversation} ->
        maybe_record_entity(
          import_job,
          "conversation",
          convo_data["id"],
          "conversation",
          conversation.id
        )

        # Import messages for this conversation
        import_conversation_messages(
          credential,
          base_url,
          conversation,
          convo_data,
          import_job
        )

      {:error, reason} ->
        ["Conversation import error: #{inspect_errors(reason)}"]
    end
  end

  defp import_conversation_messages(_credential, _base_url, conversation, convo_data, import_job) do
    messages = convo_data["messages"] || []

    Enum.flat_map(messages, fn msg ->
      attrs = %{
        "body" => msg["content"] || msg["written_by_me_body"] || "",
        "direction" => if(msg["written_by_me"], do: "sent", else: "received"),
        "sent_at" => parse_datetime(msg["written_at"]) || DateTime.utc_now()
      }

      case Kith.Conversations.add_message(conversation, attrs) do
        {:ok, message} ->
          maybe_record_entity(import_job, "message", msg["id"], "message", message.id)
          []

        {:error, reason} ->
          ["Message import error: #{inspect_errors(reason)}"]
      end
    end)
  end

  @platform_keywords [
    {"sms", "sms"},
    {"text", "sms"},
    {"whatsapp", "whatsapp"},
    {"telegram", "telegram"},
    {"email", "email"},
    {"instagram", "instagram"},
    {"messenger", "messenger"},
    {"facebook", "messenger"},
    {"signal", "signal"}
  ]

  defp normalize_conversation_platform(name) when is_binary(name) do
    normalized = String.downcase(name)

    Enum.find_value(@platform_keywords, "other", fn {keyword, platform} ->
      if String.contains?(normalized, keyword), do: platform
    end)
  end

  defp normalize_conversation_platform(_), do: "other"

  # ── Additional date/time helpers ───────────────────────────────────

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp parse_date_string(nil), do: nil

  defp parse_date_string(str) when is_binary(str) do
    case parse_date_or_datetime(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date_string(_), do: nil

  # ── Phase 13: Document import (async) ──────────────────────────────

  defp enqueue_document_imports(credential, account_id, user_id, import_job) do
    import_records =
      Repo.all(
        from(ir in Imports.ImportRecord,
          where:
            ir.import_id == ^import_job.id and
              ir.source_entity_type == "contact",
          select: {ir.source_entity_id, ir.local_entity_id}
        )
      )

    base_url = credential.url

    Enum.each(import_records, fn {source_id, local_id} ->
      url = "#{base_url}/api/contacts/#{source_id}/documents"

      case api_get_json(credential, url, []) do
        {:ok, %{"data" => docs}} when is_list(docs) and docs != [] ->
          %{
            "account_id" => account_id,
            "user_id" => user_id,
            "contact_id" => local_id,
            "import_id" => import_job.id,
            "credential_url" => credential.url,
            "credential_api_key" => credential.api_key,
            "documents" => docs
          }
          |> MonicaDocumentImportWorker.new()
          |> Oban.insert()

        _ ->
          :ok
      end
    end)
  end
end
