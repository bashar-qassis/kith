defmodule Kith.VCard.Serializer do
  @moduledoc """
  Serializes a contact (with preloaded associations) into a vCard 3.0 string.

  vCard 3.0 spec: RFC 2426
  - Line endings: CRLF (\\r\\n)
  - Property folding: at 75 octets (not implemented here — most modern parsers handle long lines)
  - Structured values use semicolons as separators
  - Special characters (semicolons, commas, backslashes, newlines) must be escaped
  """

  @crlf "\r\n"

  @doc """
  Serializes a single contact into a vCard 3.0 string.

  The contact must have the following associations preloaded:
  - :addresses
  - :contact_fields (with :contact_field_type)
  - :gender
  """
  def serialize(%{} = contact) do
    [
      "BEGIN:VCARD",
      "VERSION:3.0",
      fn_line(contact),
      n_line(contact),
      nickname_line(contact),
      bday_line(contact),
      org_line(contact),
      title_line(contact),
      note_line(contact),
      contact_field_lines(contact),
      address_lines(contact),
      "END:VCARD"
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join(@crlf)
    |> Kernel.<>(@crlf)
  end

  @doc """
  Serializes multiple contacts into a single vCard file (concatenated blocks).
  """
  def serialize_many(contacts) do
    Enum.map_join(contacts, "", &serialize/1)
  end

  # ── Identity Fields ──────────────────────────────────────────────────────

  defp fn_line(%{display_name: name}) when is_binary(name) and name != "" do
    "FN:" <> escape(name)
  end

  defp fn_line(%{first_name: first, last_name: last}) do
    name = [first, last] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

    if name != "" do
      "FN:" <> escape(name)
    end
  end

  defp n_line(contact) do
    last = escape(contact.last_name || "")
    first = escape(contact.first_name || "")
    # N: last;first;middle;prefix;suffix — we only have first/last
    "N:#{last};#{first};;;"
  end

  defp nickname_line(%{nickname: nil}), do: nil
  defp nickname_line(%{nickname: ""}), do: nil
  defp nickname_line(%{nickname: nick}), do: "NICKNAME:" <> escape(nick)

  defp bday_line(%{birthdate: nil}), do: nil

  defp bday_line(%{birthdate: date}) do
    "BDAY:" <> Date.to_iso8601(date)
  end

  defp org_line(%{company: nil}), do: nil
  defp org_line(%{company: ""}), do: nil
  defp org_line(%{company: company}), do: "ORG:" <> escape(company)

  defp title_line(%{occupation: nil}), do: nil
  defp title_line(%{occupation: ""}), do: nil
  defp title_line(%{occupation: occ}), do: "TITLE:" <> escape(occ)

  defp note_line(%{description: nil}), do: nil
  defp note_line(%{description: ""}), do: nil
  defp note_line(%{description: desc}), do: "NOTE:" <> escape(desc)

  # ── Contact Fields (TEL, EMAIL, URL, X-SOCIALPROFILE, IMPP) ────────────

  defp contact_field_lines(%{contact_fields: fields}) when is_list(fields) do
    Enum.map(fields, &contact_field_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp contact_field_lines(_), do: []

  defp contact_field_line(%{contact_field_type: %{protocol: protocol}} = field) do
    vcard_label = field.contact_field_type.vcard_label
    type_param = type_param_from_label(field.label)

    case protocol do
      "tel" ->
        "TEL#{type_param}:#{escape(field.value)}"

      "mailto" ->
        "EMAIL#{type_param}:#{escape(field.value)}"

      "https" ->
        if vcard_label && String.starts_with?(vcard_label, "X-") do
          "#{vcard_label}:#{escape(field.value)}"
        else
          "URL:#{escape(field.value)}"
        end

      "http" ->
        "URL:#{escape(field.value)}"

      _ ->
        if vcard_label do
          "#{vcard_label}:#{escape(field.value)}"
        end
    end
  end

  defp contact_field_line(_), do: nil

  defp type_param_from_label(nil), do: ""
  defp type_param_from_label(""), do: ""

  defp type_param_from_label(label) do
    type =
      case String.downcase(label) do
        "home" -> "HOME"
        "work" -> "WORK"
        "cell" -> "CELL"
        "mobile" -> "CELL"
        "fax" -> "FAX"
        "personal" -> "HOME"
        "business" -> "WORK"
        _ -> String.upcase(label)
      end

    ";TYPE=#{type}"
  end

  # ── Addresses ──────────────────────────────────────────────────────────

  defp address_lines(%{addresses: addresses}) when is_list(addresses) do
    Enum.map(addresses, &address_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp address_lines(_), do: []

  defp address_line(addr) do
    type_param = type_param_from_label(addr.label)

    # ADR: PO Box;Extended;Street;City;Region;PostalCode;Country
    components = [
      "",
      escape(addr.line2 || ""),
      escape(addr.line1 || ""),
      escape(addr.city || ""),
      escape(addr.province || ""),
      escape(addr.postal_code || ""),
      escape(addr.country || "")
    ]

    "ADR#{type_param}:" <> Enum.join(components, ";")
  end

  # ── Escaping ───────────────────────────────────────────────────────────

  @doc """
  Escapes special characters in vCard property values.

  In vCard 3.0:
  - Backslash → \\\\
  - Semicolon → \\;
  - Comma → \\,
  - Newline → \\n
  """
  def escape(nil), do: ""

  def escape(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\r\n", "\\n")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\n")
  end
end
