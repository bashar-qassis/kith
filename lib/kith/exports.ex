defmodule Kith.Exports do
  @moduledoc """
  Functions for building export data structures.
  """

  alias Kith.Contacts
  alias Kith.Repo

  @doc """
  Builds the full JSON export structure for an account.
  """
  def build_json_export(account_id) do
    import Ecto.Query

    account = Repo.get!(Kith.Accounts.Account, account_id)
    contacts = Contacts.list_contacts_with_all(account_id)

    # Load reference data
    tags =
      Kith.Contacts.Tag
      |> where([t], t.account_id == ^account_id)
      |> Repo.all()

    genders =
      Kith.Contacts.Gender
      |> where([g], is_nil(g.account_id) or g.account_id == ^account_id)
      |> Repo.all()

    relationship_types =
      Kith.Contacts.RelationshipType
      |> where([rt], is_nil(rt.account_id) or rt.account_id == ^account_id)
      |> Repo.all()

    contact_field_types =
      Kith.Contacts.ContactFieldType
      |> where([cft], is_nil(cft.account_id) or cft.account_id == ^account_id)
      |> Repo.all()

    %{
      export_version: "1.0",
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      account: %{
        name: account.name,
        timezone: Map.get(account, :timezone, nil)
      },
      contacts: Enum.map(contacts, &serialize_contact/1),
      tags: Enum.map(tags, &serialize_tag/1),
      genders: Enum.map(genders, &serialize_gender/1),
      relationship_types: Enum.map(relationship_types, &serialize_relationship_type/1),
      contact_field_types: Enum.map(contact_field_types, &serialize_contact_field_type/1)
    }
  end

  defp serialize_contact(contact) do
    serialize_contact_fields(contact)
    |> Map.merge(serialize_contact_associations(contact))
  end

  defp serialize_contact_fields(contact) do
    %{
      id: contact.id,
      first_name: contact.first_name,
      last_name: contact.last_name,
      display_name: contact.display_name,
      nickname: contact.nickname,
      birthdate: maybe_date(contact.birthdate),
      description: contact.description,
      occupation: contact.occupation,
      company: contact.company,
      favorite: contact.favorite,
      deceased: contact.deceased,
      deceased_at: maybe_date(contact.deceased_at),
      last_talked_to: maybe_datetime(contact.last_talked_to),
      gender_id: contact.gender_id
    }
  end

  defp serialize_contact_associations(contact) do
    %{
      notes: map_assoc(contact.notes, &serialize_note/1),
      life_events: map_assoc(contact.life_events, &serialize_life_event/1),
      calls: map_assoc(contact.calls, &serialize_call/1),
      addresses: map_assoc(contact.addresses, &serialize_address/1),
      contact_fields: map_assoc(contact.contact_fields, &serialize_contact_field/1),
      tags: map_assoc(contact.tags, fn t -> %{id: t.id, name: t.name} end),
      reminders: map_assoc(contact.reminders, &serialize_reminder/1),
      documents: map_assoc(contact.documents, &serialize_document/1),
      photos: map_assoc(contact.photos, &serialize_photo/1)
    }
  end

  defp map_assoc(nil, _fun), do: []
  defp map_assoc(list, fun), do: Enum.map(list, fun)

  defp maybe_date(nil), do: nil
  defp maybe_date(date), do: Date.to_iso8601(date)

  defp maybe_datetime(nil), do: nil
  defp maybe_datetime(dt), do: DateTime.to_iso8601(dt)

  defp serialize_document(d) do
    %{filename: d.file_name, file_size: d.file_size, content_type: d.content_type}
  end

  defp serialize_photo(p) do
    %{
      filename: p.file_name,
      file_size: p.file_size,
      content_type: p.content_type,
      is_cover: p.is_cover
    }
  end

  defp serialize_note(note) do
    %{
      id: note.id,
      body: note.body,
      favorite: note.favorite,
      is_private: note.is_private,
      created_at: DateTime.to_iso8601(note.inserted_at)
    }
  end

  defp serialize_life_event(le) do
    %{
      id: le.id,
      occurred_on: le.occurred_on && Date.to_iso8601(le.occurred_on),
      note: le.note,
      life_event_type_id: le.life_event_type_id
    }
  end

  defp serialize_call(call) do
    %{
      id: call.id,
      occurred_at: call.occurred_at && DateTime.to_iso8601(call.occurred_at),
      duration_mins: call.duration_mins,
      notes: call.notes,
      emotion_id: call.emotion_id,
      call_direction_id: call.call_direction_id
    }
  end

  defp serialize_address(addr) do
    %{
      id: addr.id,
      label: addr.label,
      line1: addr.line1,
      line2: addr.line2,
      city: addr.city,
      province: addr.province,
      postal_code: addr.postal_code,
      country: addr.country
    }
  end

  defp serialize_contact_field(cf) do
    %{
      id: cf.id,
      value: cf.value,
      label: cf.label,
      contact_field_type_id: cf.contact_field_type_id
    }
  end

  defp serialize_reminder(r) do
    %{
      id: r.id,
      title: Map.get(r, :title, nil),
      reminder_type: Map.get(r, :reminder_type, nil)
    }
  end

  defp serialize_tag(tag) do
    %{id: tag.id, name: tag.name, color: tag.color}
  end

  defp serialize_gender(g) do
    %{id: g.id, name: g.name}
  end

  defp serialize_relationship_type(rt) do
    %{id: rt.id, name: Map.get(rt, :name, nil)}
  end

  defp serialize_contact_field_type(cft) do
    %{id: cft.id, name: cft.name, protocol: cft.protocol, icon: cft.icon}
  end
end
