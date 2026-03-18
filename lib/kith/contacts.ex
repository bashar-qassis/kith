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
    LifeEventType
  }

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

  def create_address(%Contact{} = contact, attrs) do
    %Address{contact_id: contact.id, account_id: contact.account_id}
    |> Address.changeset(attrs)
    |> Repo.insert()
  end

  def update_address(%Address{} = address, attrs) do
    address
    |> Address.changeset(attrs)
    |> Repo.update()
  end

  def delete_address(%Address{} = address) do
    Repo.delete(address)
  end

  ## Contact Fields

  def list_contact_fields(contact_id) do
    from(cf in ContactField,
      where: cf.contact_id == ^contact_id,
      preload: [:contact_field_type]
    )
    |> Repo.all()
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

  def list_relationships(contact_id) do
    from(r in Relationship,
      where: r.contact_id == ^contact_id,
      preload: [:related_contact, :relationship_type]
    )
    |> Repo.all()
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

  def list_notes(contact_id) do
    from(n in Note, where: n.contact_id == ^contact_id, order_by: [desc: n.inserted_at])
    |> Repo.all()
  end

  def create_note(%Contact{} = contact, attrs) do
    %Note{contact_id: contact.id, account_id: contact.account_id}
    |> Note.changeset(attrs)
    |> Repo.insert()
  end

  def update_note(%Note{} = note, attrs) do
    note
    |> Note.changeset(attrs)
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

  def create_photo(%Contact{} = contact, attrs) do
    %Photo{contact_id: contact.id, account_id: contact.account_id}
    |> Photo.changeset(attrs)
    |> Repo.insert()
  end

  def delete_photo(%Photo{} = photo) do
    Repo.delete(photo)
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

  def list_currencies do
    from(c in Currency, order_by: [asc: c.code])
    |> Repo.all()
  end
end
