defmodule Kith.Contacts do
  @moduledoc """
  The Contacts context — managing contacts, addresses, contact fields,
  relationships, tags, notes, documents, photos, and reference data.
  """

  import Ecto.Query, warn: false
  import Kith.Scope
  alias Kith.Repo

  alias Kith.Contacts.{
    Contact,
    Address,
    ContactField,
    ContactFieldType,
    ImmichCandidate,
    Tag,
    Relationship,
    RelationshipType,
    Note,
    Document,
    Photo,
    Gender,
    Currency,
    Emotion,
    ActivityTypeCategory,
    LifeEventType,
    CallDirection
  }

  alias Kith.Activities.{Activity, Call}

  ## Contacts

  def list_contacts(account_id, opts \\ []) do
    order = Keyword.get(opts, :order_by, asc: :last_name, asc: :first_name)
    preloads = Keyword.get(opts, :preload, [])

    Contact
    |> scope_active(account_id)
    |> where([c], c.is_archived == false)
    |> order_by(^order)
    |> preload(^preloads)
    |> Repo.all()
  end

  def list_archived_contacts(account_id) do
    Contact
    |> scope_active(account_id)
    |> where([c], c.is_archived == true)
    |> order_by([c], asc: c.last_name, asc: c.first_name)
    |> Repo.all()
  end

  def list_trashed_contacts(account_id) do
    Contact
    |> scope_trashed(account_id)
    |> order_by([c], asc: c.last_name, asc: c.first_name)
    |> Repo.all()
  end

  def search_contacts(account_id, query) do
    search = "%#{String.replace(query, ~r/[%_\\]/, "\\\\\\0")}%"

    Contact
    |> scope_active(account_id)
    |> join(:left, [c], cf in ContactField, on: cf.contact_id == c.id)
    |> where(
      [c, cf],
      ilike(c.first_name, ^search) or
        ilike(c.last_name, ^search) or
        ilike(c.display_name, ^search) or
        ilike(c.nickname, ^search) or
        ilike(c.company, ^search) or
        ilike(cf.value, ^search)
    )
    |> distinct([c], c.id)
    |> order_by([c], asc: c.display_name)
    |> preload([:tags])
    |> Repo.all()
  end

  @doc """
  Lists contacts with cursor-based pagination.

  Returns `%{entries: [%Contact{}, ...], has_more: boolean}`.

  ## Options

    * `:limit` - page size (default 20)
    * `:after_cursor` - contact id to paginate after
    * `:order_by` - Ecto order_by clause (default `[asc: :display_name]`)
    * `:preload` - associations to preload (default `[:tags]`)
    * `:search` - search string to filter by name/company/fields
    * `:archived` - when `true`, include archived contacts (default `false`)
    * `:deceased` - when `true`, include deceased contacts (default `false`)
    * `:favorites_only` - when `true`, only return favorites (default `false`)
    * `:tag_ids` - list of tag id strings to filter by (default `[]`)
  """
  def list_contacts_paginated(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    after_cursor = Keyword.get(opts, :after_cursor, nil)
    order = Keyword.get(opts, :order_by, asc: :display_name)
    preloads = Keyword.get(opts, :preload, [:tags])
    search = Keyword.get(opts, :search, "")
    show_archived = Keyword.get(opts, :archived, false)
    show_deceased = Keyword.get(opts, :deceased, false)
    favorites_only = Keyword.get(opts, :favorites_only, false)
    tag_ids = Keyword.get(opts, :tag_ids, [])

    query =
      Contact
      |> scope_active(account_id)
      |> paginated_search(search)
      |> paginated_filter_archived(show_archived)
      |> paginated_filter_deceased(show_deceased)
      |> paginated_filter_favorites(favorites_only)
      |> paginated_filter_tags(tag_ids)
      |> paginated_cursor(after_cursor)
      |> order_by(^order)
      |> limit(^(limit + 1))
      |> preload(^preloads)

    results = Repo.all(query)
    has_more = length(results) > limit
    entries = if has_more, do: Enum.take(results, limit), else: results

    %{entries: entries, has_more: has_more}
  end

  defp paginated_search(query, ""), do: query
  defp paginated_search(query, nil), do: query

  defp paginated_search(query, search) do
    pattern = "%#{String.replace(search, ~r/[%_\\]/, "\\\\\\0")}%"

    query
    |> join(:left, [c], cf in ContactField, on: cf.contact_id == c.id)
    |> where(
      [c, cf],
      ilike(c.first_name, ^pattern) or
        ilike(c.last_name, ^pattern) or
        ilike(c.display_name, ^pattern) or
        ilike(c.nickname, ^pattern) or
        ilike(c.company, ^pattern) or
        ilike(cf.value, ^pattern)
    )
    |> distinct([c], c.id)
  end

  defp paginated_filter_archived(query, true), do: query

  defp paginated_filter_archived(query, false) do
    where(query, [c], c.is_archived == false)
  end

  defp paginated_filter_deceased(query, true), do: query

  defp paginated_filter_deceased(query, false) do
    where(query, [c], c.deceased == false)
  end

  defp paginated_filter_favorites(query, false), do: query

  defp paginated_filter_favorites(query, true) do
    where(query, [c], c.favorite == true)
  end

  defp paginated_filter_tags(query, []), do: query

  defp paginated_filter_tags(query, tag_ids) do
    int_ids =
      Enum.map(tag_ids, fn
        id when is_binary(id) -> String.to_integer(id)
        id when is_integer(id) -> id
      end)

    query
    |> join(:inner, [c], t in assoc(c, :tags))
    |> where([c, ..., t], t.id in ^int_ids)
    |> distinct([c], c.id)
  end

  defp paginated_cursor(query, nil), do: query

  defp paginated_cursor(query, cursor) do
    where(query, [c], c.id > ^cursor)
  end

  def get_contact!(account_id, id) do
    Contact
    |> scope_to_account(account_id)
    |> Repo.get!(id)
  end

  def create_contact(account_id, attrs) do
    %Contact{account_id: account_id}
    |> Contact.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_contact(%Contact{} = contact, attrs) do
    contact
    |> Contact.update_changeset(attrs)
    |> Repo.update()
  end

  def soft_delete_contact(%Contact{} = contact) do
    contact
    |> Contact.soft_delete_changeset()
    |> Repo.update()
  end

  def restore_contact(%Contact{} = contact) do
    contact
    |> Contact.restore_changeset()
    |> Repo.update()
  end

  def archive_contact(%Contact{} = contact) do
    contact
    |> Contact.archive_changeset(true)
    |> Repo.update()
  end

  def unarchive_contact(%Contact{} = contact) do
    contact
    |> Contact.archive_changeset(false)
    |> Repo.update()
  end

  def hard_delete_contact(%Contact{} = contact) do
    Repo.delete(contact)
  end

  ## Addresses

  def list_addresses(contact_id) do
    from(a in Address, where: a.contact_id == ^contact_id)
    |> Repo.all()
  end

  def get_address!(account_id, id) do
    Address |> scope_to_account(account_id) |> Repo.get!(id)
  end

  def create_address(%Contact{} = contact, attrs) do
    result =
      %Address{contact_id: contact.id, account_id: contact.account_id}
      |> Address.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, address} ->
        maybe_geocode_address(address)
        {:ok, address}

      error ->
        error
    end
  end

  def update_address(%Address{} = address, attrs) do
    result =
      address
      |> Address.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} ->
        maybe_geocode_address(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  def delete_address(%Address{} = address) do
    Repo.delete(address)
  end

  ## Contact Fields

  def list_contact_fields(contact_id) do
    from(cf in ContactField,
      where: cf.contact_id == ^contact_id,
      preload: [:contact_field_type],
      order_by: [asc: cf.contact_field_type_id]
    )
    |> Repo.all()
  end

  def get_contact_field!(account_id, id) do
    ContactField |> scope_to_account(account_id) |> Repo.get!(id)
  end

  def create_contact_field(%Contact{} = contact, attrs) do
    %ContactField{contact_id: contact.id, account_id: contact.account_id}
    |> ContactField.changeset(attrs)
    |> Repo.insert()
  end

  def update_contact_field(%ContactField{} = field, attrs) do
    field
    |> ContactField.changeset(attrs)
    |> Repo.update()
  end

  def delete_contact_field(%ContactField{} = field) do
    Repo.delete(field)
  end

  ## Tags

  def list_tags(account_id) do
    Tag
    |> scope_to_account(account_id)
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  def create_tag(account_id, attrs) do
    %Tag{account_id: account_id}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  def get_tag!(account_id, id) do
    Tag
    |> scope_to_account(account_id)
    |> Repo.get!(id)
  end

  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  def tag_contact(%Contact{} = contact, %Tag{} = tag) do
    Repo.insert_all(
      "contact_tags",
      [%{contact_id: contact.id, tag_id: tag.id}],
      on_conflict: :nothing
    )
  end

  def untag_contact(%Contact{} = contact, %Tag{} = tag) do
    from(ct in "contact_tags",
      where: ct.contact_id == ^contact.id and ct.tag_id == ^tag.id
    )
    |> Repo.delete_all()
  end

  ## Relationships

  @doc """
  Lists all relationships for a contact (both forward and reverse).
  Returns tuples of {relationship, related_contact, display_name} where
  display_name is the forward or reverse relationship type name.
  """
  def list_relationships_for_contact(contact_id) do
    forward =
      from(r in Relationship,
        where: r.contact_id == ^contact_id,
        preload: [:related_contact, :relationship_type]
      )
      |> Repo.all()
      |> Enum.map(fn r ->
        %{relationship: r, related_contact: r.related_contact, label: r.relationship_type.name}
      end)

    reverse =
      from(r in Relationship,
        where: r.related_contact_id == ^contact_id,
        preload: [:contact, :relationship_type]
      )
      |> Repo.all()
      |> Enum.map(fn r ->
        %{
          relationship: r,
          related_contact: r.contact,
          label: r.relationship_type.reverse_name
        }
      end)

    forward ++ reverse
  end

  def list_relationships(contact_id) do
    from(r in Relationship,
      where: r.contact_id == ^contact_id,
      preload: [:related_contact, :relationship_type]
    )
    |> Repo.all()
  end

  def get_relationship!(account_id, id) do
    Relationship |> scope_to_account(account_id) |> Repo.get!(id)
  end

  def create_relationship(%Contact{} = contact, attrs) do
    %Relationship{contact_id: contact.id, account_id: contact.account_id}
    |> Relationship.changeset(attrs)
    |> Repo.insert()
  end

  def delete_relationship(%Relationship{} = relationship) do
    Repo.delete(relationship)
  end

  ## Notes

  @doc """
  Lists notes for a contact. Filters out private notes not authored by current_user_id.
  """
  def list_notes(contact_id, current_user_id) do
    from(n in Note,
      where: n.contact_id == ^contact_id,
      where: n.is_private == false or n.author_id == ^current_user_id,
      order_by: [desc: n.inserted_at],
      preload: [:author]
    )
    |> Repo.all()
  end

  def get_note!(account_id, id, current_user_id) do
    note =
      Note
      |> scope_to_account(account_id)
      |> Repo.get!(id)

    if note.is_private and note.author_id != current_user_id do
      raise Ecto.NoResultsError, queryable: Note
    end

    note
  end

  def create_note(%Contact{} = contact, user_id, attrs) do
    %Note{contact_id: contact.id, account_id: contact.account_id, author_id: user_id}
    |> Note.changeset(attrs)
    |> Repo.insert()
  end

  def update_note(%Note{} = note, attrs) do
    note
    |> Note.changeset(attrs)
    |> Repo.update()
  end

  def toggle_note_favorite(%Note{} = note) do
    note
    |> Ecto.Changeset.change(favorite: !note.favorite)
    |> Repo.update()
  end

  def delete_note(%Note{} = note) do
    Repo.delete(note)
  end

  ## Documents

  def list_documents(contact_id) do
    from(d in Document, where: d.contact_id == ^contact_id, order_by: [desc: d.inserted_at])
    |> Repo.all()
  end

  def get_document!(account_id, id) do
    Document |> scope_to_account(account_id) |> Repo.get!(id)
  end

  def create_document(%Contact{} = contact, attrs) do
    %Document{contact_id: contact.id, account_id: contact.account_id}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  def delete_document(%Document{} = document) do
    Repo.delete(document)
  end

  ## Photos

  def list_photos(contact_id) do
    from(p in Photo, where: p.contact_id == ^contact_id, order_by: [desc: p.inserted_at])
    |> Repo.all()
  end

  def get_photo!(account_id, id) do
    Photo |> scope_to_account(account_id) |> Repo.get!(id)
  end

  def create_photo(%Contact{} = contact, attrs) do
    %Photo{contact_id: contact.id, account_id: contact.account_id}
    |> Photo.changeset(attrs)
    |> Repo.insert()
  end

  def delete_photo(%Photo{} = photo) do
    Repo.delete(photo)
  end

  def set_cover_photo(%Photo{} = photo) do
    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :unset_cover,
      from(p in Photo,
        where: p.contact_id == ^photo.contact_id and p.is_cover == true and p.id != ^photo.id
      ),
      set: [is_cover: false]
    )
    |> Ecto.Multi.update(:set_cover, Ecto.Changeset.change(photo, is_cover: true))
    |> Repo.transaction()
  end

  ## Reference Data

  def list_genders(account_id) do
    from(g in Gender,
      where: is_nil(g.account_id) or g.account_id == ^account_id,
      order_by: [asc: g.position, asc: g.name]
    )
    |> Repo.all()
  end

  def list_emotions(account_id) do
    from(e in Emotion,
      where: is_nil(e.account_id) or e.account_id == ^account_id,
      order_by: [asc: e.position, asc: e.name]
    )
    |> Repo.all()
  end

  def list_activity_type_categories(account_id) do
    from(a in ActivityTypeCategory,
      where: is_nil(a.account_id) or a.account_id == ^account_id,
      order_by: [asc: a.position, asc: a.name]
    )
    |> Repo.all()
  end

  def list_life_event_types(account_id) do
    from(l in LifeEventType,
      where: is_nil(l.account_id) or l.account_id == ^account_id,
      order_by: [asc: l.position, asc: l.name]
    )
    |> Repo.all()
  end

  def list_contact_field_types(account_id) do
    from(cft in ContactFieldType,
      where: is_nil(cft.account_id) or cft.account_id == ^account_id,
      order_by: [asc: cft.position, asc: cft.name]
    )
    |> Repo.all()
  end

  def list_relationship_types(account_id) do
    from(rt in RelationshipType,
      where: is_nil(rt.account_id) or rt.account_id == ^account_id,
      order_by: [asc: rt.position, asc: rt.name]
    )
    |> Repo.all()
  end

  def list_call_directions do
    from(cd in CallDirection, order_by: [asc: cd.position])
    |> Repo.all()
  end

  def list_currencies do
    from(c in Currency, order_by: [asc: c.code])
    |> Repo.all()
  end

  ## Immich Review

  @doc "Lists contacts needing Immich review for an account."
  def list_needs_review(account_id) do
    Contact
    |> where([c], c.account_id == ^account_id)
    |> where([c], c.immich_status == "needs_review")
    |> where([c], is_nil(c.deleted_at))
    |> order_by([c], asc: c.display_name)
    |> preload(:immich_candidates)
    |> Repo.all()
  end

  @doc "Returns count of contacts needing Immich review."
  def count_needs_review(account_id) do
    Contact
    |> where([c], c.account_id == ^account_id)
    |> where([c], c.immich_status == "needs_review")
    |> where([c], is_nil(c.deleted_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Confirms a link between a contact and an Immich person.
  Sets status to linked, stores person ID/URL, clears candidates.
  """
  def confirm_immich_link(%Contact{} = contact, immich_person_id, immich_person_url) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :contact,
      Contact.update_changeset(contact, %{
        immich_status: "linked",
        immich_person_id: immich_person_id,
        immich_person_url: immich_person_url
      })
    )
    |> Ecto.Multi.update_all(
      :clear_candidates,
      fn _ ->
        from(ic in ImmichCandidate,
          where: ic.contact_id == ^contact.id and ic.account_id == ^contact.account_id
        )
      end,
      set: [status: "accepted"]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{contact: contact}} -> {:ok, contact}
      {:error, :contact, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Rejects a specific Immich candidate."
  def reject_immich_candidate(%ImmichCandidate{} = candidate) do
    candidate
    |> ImmichCandidate.changeset(%{status: "rejected"})
    |> Repo.update()
    |> case do
      {:ok, _} ->
        # If no pending candidates remain, set contact to unlinked
        pending_count =
          ImmichCandidate
          |> where([ic], ic.contact_id == ^candidate.contact_id)
          |> where([ic], ic.account_id == ^candidate.account_id)
          |> where([ic], ic.status == "pending")
          |> Repo.aggregate(:count)

        if pending_count == 0 do
          contact = Repo.get!(Contact, candidate.contact_id)

          contact
          |> Contact.update_changeset(%{immich_status: "unlinked"})
          |> Repo.update()
        else
          {:ok, candidate}
        end

      error ->
        error
    end
  end

  @doc "Unlinks a confirmed Immich connection from a contact."
  def unlink_immich(%Contact{} = contact) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :contact,
      Contact.update_changeset(contact, %{
        immich_status: "unlinked",
        immich_person_id: nil,
        immich_person_url: nil
      })
    )
    |> Ecto.Multi.delete_all(
      :clear_candidates,
      from(ic in ImmichCandidate,
        where: ic.contact_id == ^contact.id and ic.account_id == ^contact.account_id
      )
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{contact: contact}} -> {:ok, contact}
      {:error, :contact, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Lists pending Immich candidates for a contact."
  def list_pending_candidates(account_id, contact_id) do
    ImmichCandidate
    |> where([ic], ic.account_id == ^account_id)
    |> where([ic], ic.contact_id == ^contact_id)
    |> where([ic], ic.status == "pending")
    |> order_by([ic], desc: ic.suggested_at)
    |> Repo.all()
  end

  ## Genders CRUD

  @doc "Gets a gender by ID, scoped to account (includes global genders)."
  def get_gender!(account_id, id) do
    from(g in Gender,
      where: g.id == ^id,
      where: is_nil(g.account_id) or g.account_id == ^account_id
    )
    |> Repo.one!()
  end

  @doc "Creates a custom gender for the account."
  def create_gender(account_id, attrs) do
    %Gender{account_id: account_id}
    |> Gender.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a custom gender. Cannot modify global genders (account_id IS NULL)."
  def update_gender(%Gender{account_id: nil}, _attrs), do: {:error, :global_read_only}

  def update_gender(%Gender{} = gender, attrs) do
    gender
    |> Gender.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a custom gender. Cannot delete global genders.
  Cannot delete if any contact in the account has this gender assigned.
  """
  def delete_gender(%Gender{account_id: nil}), do: {:error, :global_read_only}

  def delete_gender(%Gender{} = gender) do
    in_use? =
      Repo.exists?(
        from(c in Contact,
          where: c.gender_id == ^gender.id and c.account_id == ^gender.account_id
        )
      )

    if in_use? do
      {:error, :in_use}
    else
      Repo.delete(gender)
    end
  end

  @doc "Bulk updates position values for account-specific genders."
  def reorder_genders(account_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, position} ->
        from(g in Gender,
          where: g.id == ^id and g.account_id == ^account_id
        )
        |> Repo.update_all(set: [position: position])
      end)
    end)
  end

  ## Relationship Types CRUD

  @doc "Gets a relationship type by ID, scoped to account (includes global)."
  def get_relationship_type!(account_id, id) do
    from(rt in RelationshipType,
      where: rt.id == ^id,
      where: is_nil(rt.account_id) or rt.account_id == ^account_id
    )
    |> Repo.one!()
  end

  @doc "Creates a custom relationship type for the account."
  def create_relationship_type(account_id, attrs) do
    %RelationshipType{account_id: account_id}
    |> RelationshipType.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a custom relationship type. Cannot modify global types."
  def update_relationship_type(%RelationshipType{account_id: nil}, _attrs),
    do: {:error, :global_read_only}

  def update_relationship_type(%RelationshipType{} = rt, attrs) do
    rt
    |> RelationshipType.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a custom relationship type. Cannot delete global types or types in use."
  def delete_relationship_type(%RelationshipType{account_id: nil}),
    do: {:error, :global_read_only}

  def delete_relationship_type(%RelationshipType{} = rt) do
    in_use? =
      Repo.exists?(
        from(r in Relationship,
          where: r.relationship_type_id == ^rt.id and r.account_id == ^rt.account_id
        )
      )

    if in_use? do
      {:error, :in_use}
    else
      Repo.delete(rt)
    end
  end

  ## Contact Field Types CRUD

  @doc "Gets a contact field type by ID, scoped to account (includes global)."
  def get_contact_field_type!(account_id, id) do
    from(cft in ContactFieldType,
      where: cft.id == ^id,
      where: is_nil(cft.account_id) or cft.account_id == ^account_id
    )
    |> Repo.one!()
  end

  @doc "Creates a custom contact field type for the account."
  def create_contact_field_type(account_id, attrs) do
    %ContactFieldType{account_id: account_id}
    |> ContactFieldType.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a custom contact field type. Cannot modify global types."
  def update_contact_field_type(%ContactFieldType{account_id: nil}, _attrs),
    do: {:error, :global_read_only}

  def update_contact_field_type(%ContactFieldType{} = cft, attrs) do
    cft
    |> ContactFieldType.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a custom contact field type. Cannot delete global types or types in use."
  def delete_contact_field_type(%ContactFieldType{account_id: nil}),
    do: {:error, :global_read_only}

  def delete_contact_field_type(%ContactFieldType{} = cft) do
    in_use? =
      Repo.exists?(
        from(cf in ContactField,
          where: cf.contact_field_type_id == ^cft.id,
          join: c in Contact,
          on: cf.contact_id == c.id,
          where: c.account_id == ^cft.account_id
        )
      )

    if in_use? do
      {:error, :in_use}
    else
      Repo.delete(cft)
    end
  end

  @doc "Bulk updates position values for account-specific contact field types."
  def reorder_contact_field_types(account_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, position} ->
        from(cft in ContactFieldType,
          where: cft.id == ^id and cft.account_id == ^account_id
        )
        |> Repo.update_all(set: [position: position])
      end)
    end)
  end

  ## Tags Management (Settings)

  @doc "Returns tags with contact counts, ordered by name."
  def list_tags_with_counts(account_id) do
    from(t in Tag,
      where: t.account_id == ^account_id,
      left_join: ct in "contact_tags",
      on: ct.tag_id == t.id,
      group_by: t.id,
      select: %{tag: t, count: count(ct.contact_id)},
      order_by: [asc: t.name]
    )
    |> Repo.all()
  end

  @doc "Returns the count of contacts with this tag."
  def tag_usage_count(%Tag{} = tag) do
    from(ct in "contact_tags", where: ct.tag_id == ^tag.id)
    |> Repo.aggregate(:count)
  end

  @doc "Renames a tag. Validates new name is unique per account (case-insensitive)."
  def rename_tag(%Tag{} = tag, new_name) do
    tag
    |> Tag.changeset(%{name: new_name})
    |> Repo.update()
  end

  @doc """
  Deletes a tag and removes it from all contacts (CASCADE handles join table).
  """
  def delete_tag_with_removal(%Tag{} = tag) do
    Repo.delete(tag)
  end

  @doc """
  Merges source tag into target tag: moves all contact associations from
  source to target, then deletes source. Handles duplicates via ON CONFLICT.
  Uses Ecto.Multi for atomicity.
  """
  def merge_tags(account_id, %Tag{} = source, %Tag{} = target) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:move_associations, fn repo, _changes ->
      # Get all contact_ids associated with source tag
      source_contact_ids =
        from(ct in "contact_tags",
          where: ct.tag_id == ^source.id,
          select: ct.contact_id
        )
        |> repo.all()

      # Insert associations to target, ignoring duplicates
      entries = Enum.map(source_contact_ids, fn cid -> %{contact_id: cid, tag_id: target.id} end)

      if entries != [] do
        repo.insert_all("contact_tags", entries, on_conflict: :nothing)
      end

      {:ok, length(source_contact_ids)}
    end)
    |> Ecto.Multi.run(:delete_source_associations, fn repo, _changes ->
      {count, _} =
        from(ct in "contact_tags", where: ct.tag_id == ^source.id)
        |> repo.delete_all()

      {:ok, count}
    end)
    |> Ecto.Multi.delete(:delete_source, source)
    |> Repo.transaction()
    |> case do
      {:ok, %{delete_source: _tag}} -> {:ok, target}
      {:error, step, reason, _changes} -> {:error, {step, reason}}
    end
  end

  # -- Geocoding integration --

  require Logger

  defp maybe_geocode_address(%Address{} = address) do
    if Kith.Geocoding.enabled?() do
      address_string = format_address_for_geocoding(address)

      if address_string != "" do
        Task.Supervisor.start_child(Kith.TaskSupervisor, fn ->
          case Kith.Geocoding.geocode(address_string) do
            {:ok, %{lat: lat, lng: lng}} ->
              address
              |> Address.changeset(%{latitude: lat, longitude: lng})
              |> Repo.update()

            {:error, reason} ->
              Logger.warning("Geocoding failed for address #{address.id}: #{inspect(reason)}")
          end
        end)
      end
    end
  end

  defp format_address_for_geocoding(%Address{} = addr) do
    [addr.line1, addr.line2, addr.city, addr.province, addr.postal_code, addr.country]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  # ── Export Helpers ─────────────────────────────────────────────────────

  @doc """
  Gets a single contact by ID with optional preloads. Returns nil if not found
  or soft-deleted.
  """
  def get_contact(account_id, id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    Contact
    |> scope_active(account_id)
    |> preload(^preloads)
    |> Repo.get(id)
  end

  @doc """
  Returns a stream of all non-deleted contacts for an account.
  Must be called inside a `Repo.transaction/1`.
  """
  def stream_all_contacts(account_id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    Contact
    |> scope_active(account_id)
    |> order_by([c], asc: c.last_name, asc: c.first_name)
    |> preload(^preloads)
    |> Repo.stream(max_rows: 100)
  end

  @doc """
  Returns a stream of contacts matching the given IDs for an account.
  Must be called inside a `Repo.transaction/1`.
  """
  def stream_contacts_by_ids(account_id, ids, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    Contact
    |> scope_active(account_id)
    |> where([c], c.id in ^ids)
    |> order_by([c], asc: c.last_name, asc: c.first_name)
    |> preload(^preloads)
    |> Repo.stream(max_rows: 100)
  end

  @doc """
  Counts all non-deleted contacts for an account.
  """
  def count_contacts(account_id) do
    Contact
    |> scope_active(account_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Lists all non-deleted contacts with all sub-entities preloaded.
  Used for JSON export of small accounts.
  """
  def list_contacts_with_all(account_id) do
    Contact
    |> scope_active(account_id)
    |> order_by([c], asc: c.last_name, asc: c.first_name)
    |> preload([
      :addresses,
      :tags,
      :gender,
      contact_fields: :contact_field_type,
      notes: [],
      documents: [],
      photos: [],
      life_events: :life_event_type,
      calls: [:emotion, :call_direction],
      reminders: []
    ])
    |> Repo.all()
  end

  # ── Import Helpers ─────────────────────────────────────────────────────

  @doc """
  Checks if a contact with the given email or name already exists in the account.
  Returns true if a duplicate is found.
  """
  def contact_exists?(account_id, %{} = attrs) do
    emails = Map.get(attrs, :emails, [])
    first_name = Map.get(attrs, :first_name)
    last_name = Map.get(attrs, :last_name)

    email_values = Enum.map(emails, & &1.value) |> Enum.reject(&is_nil/1)

    query =
      Contact
      |> scope_active(account_id)

    email_match =
      if email_values != [] do
        from(c in query,
          join: cf in ContactField,
          on: cf.contact_id == c.id,
          join: cft in ContactFieldType,
          on: cf.contact_field_type_id == cft.id,
          where: cft.protocol == "mailto" and cf.value in ^email_values
        )
        |> Repo.exists?()
      else
        false
      end

    name_match =
      if first_name && last_name do
        from(c in query,
          where:
            fragment("LOWER(?)", c.first_name) == ^String.downcase(first_name) and
              fragment("LOWER(?)", c.last_name) == ^String.downcase(last_name)
        )
        |> Repo.exists?()
      else
        false
      end

    email_match || name_match
  end

  @doc """
  Creates a contact from parsed vCard data. Used by the import flow.
  Does not create birthday reminders (intentional for bulk import).
  """
  def import_contact(account_id, %{} = parsed) do
    Repo.transaction(fn ->
      contact_attrs = %{
        first_name: parsed.first_name,
        last_name: parsed.last_name,
        nickname: parsed.nickname,
        birthdate: parsed.birthdate,
        company: parsed.company,
        occupation: parsed.occupation,
        description: parsed.description,
        account_id: account_id
      }

      contact =
        %Contact{}
        |> Contact.create_changeset(contact_attrs)
        |> Ecto.Changeset.put_change(:account_id, account_id)
        |> Repo.insert!()

      # Create email contact fields
      create_imported_contact_fields(contact, account_id, parsed.emails, "mailto")

      # Create phone contact fields
      create_imported_contact_fields(contact, account_id, parsed.phones, "tel")

      # Create URL contact fields
      create_imported_contact_fields(contact, account_id, parsed.urls, "https")

      # Create addresses
      Enum.each(parsed.addresses, fn addr ->
        %Address{}
        |> Address.changeset(Map.merge(addr, %{contact_id: contact.id, account_id: account_id}))
        |> Repo.insert!()
      end)

      contact
    end)
  end

  defp create_imported_contact_fields(contact, account_id, fields, protocol) do
    # Find or use the first contact field type matching the protocol
    field_type =
      ContactFieldType
      |> where([t], t.protocol == ^protocol)
      |> where([t], is_nil(t.account_id) or t.account_id == ^account_id)
      |> order_by([t], asc: t.position)
      |> limit(1)
      |> Repo.one()

    if field_type do
      Enum.each(fields, fn %{value: value, label: label} ->
        %ContactField{}
        |> ContactField.changeset(%{
          value: value,
          label: label,
          contact_id: contact.id,
          account_id: account_id,
          contact_field_type_id: field_type.id
        })
        |> Repo.insert!()
      end)
    end
  end

  # ── Contact Merge ──────────────────────────────────────────────────────

  @doc """
  Merges two contacts. The survivor keeps chosen field values and receives
  all sub-entities from the non-survivor. The non-survivor is soft-deleted.

  `field_choices` is a map of `%{"field_name" => "survivor" | "non_survivor"}`
  indicating which contact's value to keep for each identity field.

  Both contacts must belong to the same account.

  Returns `{:ok, %{survivor: contact}}` or `{:error, step, changeset, changes}`.
  """
  def merge_contacts(survivor_id, non_survivor_id, field_choices \\ %{}) do
    alias Kith.Activities.{Call, LifeEvent}

    with {:ok, survivor} <- fetch_active_contact(survivor_id),
         {:ok, non_survivor} <- fetch_active_contact(non_survivor_id),
         :ok <- validate_merge(survivor, non_survivor) do
      account_id = survivor.account_id

      Ecto.Multi.new()
      # (a) Update survivor identity fields
      |> Ecto.Multi.run(:update_survivor_fields, fn _repo, _changes ->
        update_survivor_fields(survivor, non_survivor, field_choices)
      end)
      # (b) Remap notes
      |> Ecto.Multi.update_all(
        :remap_notes,
        fn _changes ->
          from(n in Note, where: n.contact_id == ^non_survivor.id)
        end,
        set: [contact_id: survivor.id]
      )
      # Remap activity_contacts
      |> Ecto.Multi.run(:remap_activity_contacts, fn repo, _changes ->
        # Delete activity_contacts that would create duplicates
        repo.query(
          "DELETE FROM activity_contacts WHERE contact_id = $1 AND activity_id IN (SELECT activity_id FROM activity_contacts WHERE contact_id = $2)",
          [non_survivor.id, survivor.id]
        )

        repo.update_all(
          from(ac in "activity_contacts", where: ac.contact_id == ^non_survivor.id),
          set: [contact_id: survivor.id]
        )

        {:ok, :done}
      end)
      # Remap calls
      |> Ecto.Multi.update_all(
        :remap_calls,
        fn _changes ->
          from(c in Call, where: c.contact_id == ^non_survivor.id)
        end,
        set: [contact_id: survivor.id]
      )
      # Remap life_events
      |> Ecto.Multi.update_all(
        :remap_life_events,
        fn _changes ->
          from(le in LifeEvent, where: le.contact_id == ^non_survivor.id)
        end,
        set: [contact_id: survivor.id]
      )
      # Remap documents
      |> Ecto.Multi.update_all(
        :remap_documents,
        fn _changes ->
          from(d in Document, where: d.contact_id == ^non_survivor.id)
        end,
        set: [contact_id: survivor.id]
      )
      # Remap photos
      |> Ecto.Multi.update_all(
        :remap_photos,
        fn _changes ->
          from(p in Photo, where: p.contact_id == ^non_survivor.id)
        end,
        set: [contact_id: survivor.id]
      )
      # Remap addresses
      |> Ecto.Multi.update_all(
        :remap_addresses,
        fn _changes ->
          from(a in Address, where: a.contact_id == ^non_survivor.id)
        end,
        set: [contact_id: survivor.id]
      )
      # Remap contact_fields (then deduplicate)
      |> Ecto.Multi.run(:remap_contact_fields, fn repo, _changes ->
        # Move all contact fields
        repo.update_all(
          from(cf in ContactField, where: cf.contact_id == ^non_survivor.id),
          set: [contact_id: survivor.id]
        )

        # Deduplicate: remove exact dupes (same type + same value)
        repo.query(
          """
          DELETE FROM contact_fields
          WHERE id IN (
            SELECT cf.id FROM contact_fields cf
            WHERE cf.contact_id = $1
            AND EXISTS (
              SELECT 1 FROM contact_fields cf2
              WHERE cf2.contact_id = $1
              AND cf2.contact_field_type_id = cf.contact_field_type_id
              AND cf2.value = cf.value
              AND cf2.id < cf.id
            )
          )
          """,
          [survivor.id]
        )

        {:ok, :done}
      end)
      # Remap contact_tags (handle duplicates)
      |> Ecto.Multi.run(:remap_contact_tags, fn repo, _changes ->
        # Delete tags that already exist on survivor
        repo.query(
          "DELETE FROM contact_tags WHERE contact_id = $1 AND tag_id IN (SELECT tag_id FROM contact_tags WHERE contact_id = $2)",
          [non_survivor.id, survivor.id]
        )

        # Move remaining tags
        repo.update_all(
          from(ct in "contact_tags", where: ct.contact_id == ^non_survivor.id),
          set: [contact_id: survivor.id]
        )

        {:ok, :done}
      end)
      # Remap reminders
      |> Ecto.Multi.update_all(
        :remap_reminders,
        fn _changes ->
          from(r in Kith.Reminders.Reminder, where: r.contact_id == ^non_survivor.id)
        end,
        set: [contact_id: survivor.id]
      )
      # (c) Remap relationships
      |> Ecto.Multi.run(:remap_relationships, fn repo, _changes ->
        remap_relationships(repo, survivor, non_survivor)
      end)
      # (d) Cancel Oban jobs for non-survivor reminders
      |> Ecto.Multi.run(:cancel_oban_jobs, fn _repo, _changes ->
        Kith.Reminders.cancel_all_for_contact(non_survivor.id, account_id)
      end)
      # (f) Update survivor's last_talked_to
      |> Ecto.Multi.run(:update_last_talked_to, fn repo, _changes ->
        more_recent = most_recent_date(survivor.last_talked_to, non_survivor.last_talked_to)

        if more_recent != survivor.last_talked_to do
          survivor
          |> Ecto.Changeset.change(%{last_talked_to: more_recent})
          |> repo.update()
        else
          {:ok, survivor}
        end
      end)
      # (e) Soft-delete non-survivor
      |> Ecto.Multi.run(:soft_delete_non_survivor, fn repo, _changes ->
        non_survivor
        |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
        |> repo.update()
      end)
      |> Repo.transaction()
    end
  end

  defp fetch_active_contact(id) do
    contact = Repo.get(Contact, id)

    cond do
      is_nil(contact) -> {:error, :not_found}
      contact.deleted_at != nil -> {:error, :trashed}
      true -> {:ok, contact}
    end
  end

  defp validate_merge(survivor, non_survivor) do
    cond do
      survivor.id == non_survivor.id -> {:error, :same_contact}
      survivor.account_id != non_survivor.account_id -> {:error, :different_accounts}
      true -> :ok
    end
  end

  defp update_survivor_fields(survivor, non_survivor, field_choices) do
    mergeable_fields = ~w(first_name last_name nickname birthdate description
                          occupation company avatar)a

    changes =
      Enum.reduce(mergeable_fields, %{}, fn field, acc ->
        field_str = Atom.to_string(field)

        case Map.get(field_choices, field_str, "survivor") do
          "non_survivor" ->
            Map.put(acc, field, Map.get(non_survivor, field))

          _ ->
            acc
        end
      end)

    if map_size(changes) > 0 do
      survivor
      |> Ecto.Changeset.change(changes)
      |> Repo.update()
    else
      {:ok, survivor}
    end
  end

  defp remap_relationships(repo, survivor, non_survivor) do
    # Remap forward relationships (contact_id = non_survivor)
    # First delete any that would create duplicates or self-references
    repo.query(
      """
      DELETE FROM relationships WHERE contact_id = $1
      AND (
        related_contact_id = $2
        OR (related_contact_id, relationship_type_id) IN (
          SELECT related_contact_id, relationship_type_id
          FROM relationships WHERE contact_id = $2
        )
      )
      """,
      [non_survivor.id, survivor.id]
    )

    repo.update_all(
      from(r in Relationship, where: r.contact_id == ^non_survivor.id),
      set: [contact_id: survivor.id]
    )

    # Remap reverse relationships (related_contact_id = non_survivor)
    repo.query(
      """
      DELETE FROM relationships WHERE related_contact_id = $1
      AND (
        contact_id = $2
        OR (contact_id, relationship_type_id) IN (
          SELECT contact_id, relationship_type_id
          FROM relationships WHERE related_contact_id = $2
        )
      )
      """,
      [non_survivor.id, survivor.id]
    )

    repo.update_all(
      from(r in Relationship, where: r.related_contact_id == ^non_survivor.id),
      set: [related_contact_id: survivor.id]
    )

    # Clean up any self-referential relationships
    repo.delete_all(
      from(r in Relationship,
        where: r.contact_id == ^survivor.id and r.related_contact_id == ^survivor.id
      )
    )

    {:ok, :done}
  end

  defp most_recent_date(nil, date), do: date
  defp most_recent_date(date, nil), do: date

  defp most_recent_date(date1, date2) do
    if DateTime.compare(date1, date2) == :gt, do: date1, else: date2
  end

  @doc """
  Returns a dry-run preview of what a merge would do.
  Does NOT modify any data.
  """
  def merge_preview(survivor_id, non_survivor_id) do
    with {:ok, survivor} <- fetch_active_contact(survivor_id),
         {:ok, non_survivor} <- fetch_active_contact(non_survivor_id),
         :ok <- validate_merge(survivor, non_survivor) do
      alias Kith.Activities.{Call, LifeEvent}

      notes_count =
        Repo.aggregate(from(n in Note, where: n.contact_id == ^non_survivor.id), :count)

      activities_count =
        Repo.aggregate(
          from(ac in "activity_contacts",
            where: ac.contact_id == ^non_survivor.id,
            select: count()
          ),
          :count
        )

      calls_count =
        Repo.aggregate(from(c in Call, where: c.contact_id == ^non_survivor.id), :count)

      life_events_count =
        Repo.aggregate(from(le in LifeEvent, where: le.contact_id == ^non_survivor.id), :count)

      documents_count =
        Repo.aggregate(from(d in Document, where: d.contact_id == ^non_survivor.id), :count)

      photos_count =
        Repo.aggregate(from(p in Photo, where: p.contact_id == ^non_survivor.id), :count)

      addresses_count =
        Repo.aggregate(from(a in Address, where: a.contact_id == ^non_survivor.id), :count)

      contact_fields_count =
        Repo.aggregate(
          from(cf in ContactField, where: cf.contact_id == ^non_survivor.id),
          :count
        )

      reminders_count =
        Repo.aggregate(
          from(r in Kith.Reminders.Reminder, where: r.contact_id == ^non_survivor.id),
          :count
        )

      # Tags on non-survivor not on survivor
      survivor_tag_ids =
        from(ct in "contact_tags",
          where: ct.contact_id == ^survivor.id,
          select: ct.tag_id
        )
        |> Repo.all()

      tags_to_merge =
        from(ct in "contact_tags",
          where: ct.contact_id == ^non_survivor.id and ct.tag_id not in ^survivor_tag_ids,
          select: count()
        )
        |> Repo.one()

      tags_duplicate =
        from(ct in "contact_tags",
          where: ct.contact_id == ^non_survivor.id and ct.tag_id in ^survivor_tag_ids,
          select: count()
        )
        |> Repo.one()

      # Relationship analysis
      {rels_to_remap, rels_to_dedup} = analyze_relationships(survivor, non_survivor)

      {:ok,
       %{
         notes: notes_count,
         activities: activities_count,
         calls: calls_count,
         life_events: life_events_count,
         documents: documents_count,
         photos: photos_count,
         addresses: addresses_count,
         contact_fields: contact_fields_count,
         reminders: reminders_count,
         tags_to_merge: tags_to_merge,
         tags_duplicate: tags_duplicate,
         relationships_to_remap: length(rels_to_remap),
         relationships_to_dedup: length(rels_to_dedup),
         duplicate_relationships: rels_to_dedup
       }}
    end
  end

  defp analyze_relationships(survivor, non_survivor) do
    non_survivor_rels =
      from(r in Relationship,
        where: r.contact_id == ^non_survivor.id or r.related_contact_id == ^non_survivor.id,
        preload: [:relationship_type, :contact, :related_contact]
      )
      |> Repo.all()

    survivor_rels =
      from(r in Relationship,
        where: r.contact_id == ^survivor.id or r.related_contact_id == ^survivor.id
      )
      |> Repo.all()

    # Find exact duplicates (same related party + same type after remapping)
    survivor_rel_keys =
      Enum.map(survivor_rels, fn r ->
        {normalize_rel_contact(r, survivor.id), r.relationship_type_id}
      end)
      |> MapSet.new()

    {to_dedup, to_remap} =
      Enum.split_with(non_survivor_rels, fn r ->
        remapped_other = normalize_rel_contact_for_merge(r, non_survivor.id, survivor.id)
        key = {remapped_other, r.relationship_type_id}
        MapSet.member?(survivor_rel_keys, key) || remapped_other == survivor.id
      end)

    {to_remap, to_dedup}
  end

  defp normalize_rel_contact(rel, contact_id) do
    if rel.contact_id == contact_id, do: rel.related_contact_id, else: rel.contact_id
  end

  defp normalize_rel_contact_for_merge(rel, non_survivor_id, survivor_id) do
    other = normalize_rel_contact(rel, non_survivor_id)
    if other == survivor_id, do: survivor_id, else: other
  end

  # ── Dashboard helpers ──────────────────────────────────────────────────

  @doc "Returns the last N contacts modified (by updated_at), preloading tags."
  def recent_contacts(account_id, limit \\ 5) do
    Contact
    |> scope_active(account_id)
    |> where([c], c.is_archived == false)
    |> order_by([c], desc: c.updated_at)
    |> limit(^limit)
    |> preload(:tags)
    |> Repo.all()
  end

  @doc "Returns total active (non-archived, non-trashed) contact count."
  def contact_count(account_id) do
    Contact
    |> scope_active(account_id)
    |> where([c], c.is_archived == false)
    |> Repo.aggregate(:count)
  end

  @doc "Returns total note count for an account."
  def note_count(account_id) do
    Note
    |> where([n], n.account_id == ^account_id)
    |> Repo.aggregate(:count)
  end

  @doc "Returns recent notes/activities/calls across all contacts for the activity feed."
  def recent_activity(account_id, limit \\ 10) do
    notes_query =
      from n in Note,
        where: n.account_id == ^account_id,
        select: %{
          id: n.id,
          type: "note",
          contact_id: n.contact_id,
          title: fragment("substring(? from 1 for 100)", n.body),
          occurred_at: n.inserted_at,
          inserted_at: n.inserted_at
        }

    activities_query =
      from a in Activity,
        join: ac in "activity_contacts",
        on: ac.activity_id == a.id,
        where: a.account_id == ^account_id,
        select: %{
          id: a.id,
          type: "activity",
          contact_id: ac.contact_id,
          title: a.title,
          occurred_at: a.occurred_at,
          inserted_at: a.inserted_at
        }

    calls_query =
      from c in Call,
        where: c.account_id == ^account_id,
        select: %{
          id: c.id,
          type: "call",
          contact_id: c.contact_id,
          title: fragment("'Call'"),
          occurred_at: c.occurred_at,
          inserted_at: c.inserted_at
        }

    union_query =
      notes_query
      |> union_all(^activities_query)
      |> union_all(^calls_query)

    from(sub in subquery(union_query),
      order_by: [desc: sub.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end
end
