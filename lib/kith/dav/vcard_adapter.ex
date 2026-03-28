defmodule Kith.DAV.VCardAdapter do
  @moduledoc """
  Bidirectional conversion between Kith contacts and vCard 3.0 format
  for the CardDAV server.

  Delegates to the existing `Kith.VCard.Serializer` and `Kith.VCard.Parser`
  modules, adding a UID property for CardDAV identification and adapting the
  parser output into changeset-compatible attribute maps.
  """

  alias Kith.Contacts.Contact
  alias Kith.Repo
  alias Kith.VCard.{Parser, Serializer}

  @vcard_preloads [:addresses, :gender, contact_fields: :contact_field_type]

  @doc """
  Converts a Kith contact to a vCard 3.0 string with a CardDAV UID.

  Preloads required associations if not already loaded.
  """
  def contact_to_vcard(%Contact{} = contact) do
    contact = Repo.preload(contact, @vcard_preloads)

    # Use the existing serializer and inject UID after VERSION line
    vcard = Serializer.serialize(contact)
    inject_uid(vcard, contact.id)
  end

  @doc """
  Parses a vCard string into scalar attrs and nested data.

  Returns `{scalar_attrs, nested_data}` on success or `:error` on parse failure.

  `scalar_attrs` is a map suitable for `Contacts.create_contact/2`.
  `nested_data` contains `:emails`, `:phones`, `:urls`, `:addresses`, `:uid`.
  """
  def vcard_to_attrs(vcard_string, opts \\ []) do
    case Parser.parse(vcard_string) do
      {:ok, [parsed | _]} ->
        attrs = %{
          "first_name" => parsed.first_name,
          "last_name" => parsed.last_name,
          "nickname" => parsed.nickname,
          "company" => parsed.company,
          "occupation" => parsed.occupation,
          "description" => parsed.description
        }

        attrs =
          if parsed.birthdate do
            Map.put(attrs, "birthdate", Date.to_iso8601(parsed.birthdate))
          else
            attrs
          end

        scalar_attrs = maybe_strip_nils(attrs, opts)

        nested_data = %{
          emails: parsed.emails || [],
          phones: parsed.phones || [],
          urls: parsed.urls || [],
          addresses: parsed.addresses || [],
          uid: parsed.uid
        }

        {scalar_attrs, nested_data}

      _ ->
        :error
    end
  end

  # ── Private ────────────────────────────────────────────────────────────

  # Inserts a UID line after the VERSION line in the serialized vCard.
  defp inject_uid(vcard, contact_id) do
    uid_line = "UID:kith-contact-#{contact_id}"

    vcard
    |> String.replace(
      "VERSION:3.0\r\n",
      "VERSION:3.0\r\n#{uid_line}\r\n"
    )
  end

  defp maybe_strip_nils(attrs, opts) do
    if Keyword.get(opts, :strip_nils, true) do
      attrs |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
    else
      attrs
    end
  end
end
