defmodule Kith.VCard.Parser do
  @moduledoc """
  Parses vCard 3.0 and 4.0 files into structured maps.

  Handles:
  - Single and multi-contact .vcf files
  - Property parameters (TYPE=HOME, etc.)
  - Line unfolding (continuation lines starting with space/tab)
  - Both CRLF and LF line endings
  """

  @doc """
  Parses a vCard file string into a list of contact maps.

  Returns `{:ok, contacts}` or `{:error, reason}`.

  Each contact map has keys:
  - :first_name, :last_name, :display_name, :nickname
  - :birthdate (Date or nil)
  - :company, :occupation, :description
  - :emails (list of %{value, label})
  - :phones (list of %{value, label})
  - :urls (list of %{value, label})
  - :addresses (list of %{label, line1, line2, city, province, postal_code, country})
  """
  def parse(data) when is_binary(data) do
    try do
      contacts =
        data
        |> normalize_line_endings()
        |> unfold_lines()
        |> split_vcards()
        |> Enum.map(&parse_vcard/1)
        |> Enum.reject(&is_nil/1)

      {:ok, contacts}
    rescue
      e -> {:error, "Failed to parse vCard file: #{Exception.message(e)}"}
    end
  end

  # ── Preprocessing ──────────────────────────────────────────────────────

  defp normalize_line_endings(data) do
    data
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
  end

  defp unfold_lines(data) do
    # RFC 2425: continuation lines start with a single space or tab
    String.replace(data, ~r/\n[ \t]/, "")
  end

  defp split_vcards(data) do
    ~r/BEGIN:VCARD\n(.*?)END:VCARD/si
    |> Regex.scan(data, capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> Enum.reject(&is_nil/1)
  end

  # ── Single vCard Parsing ───────────────────────────────────────────────

  defp parse_vcard(block) do
    lines = String.split(block, "\n", trim: true)

    base = %{
      first_name: nil,
      last_name: nil,
      display_name: nil,
      nickname: nil,
      birthdate: nil,
      company: nil,
      occupation: nil,
      description: nil,
      emails: [],
      phones: [],
      urls: [],
      addresses: []
    }

    Enum.reduce(lines, base, &parse_line/2)
  end

  defp parse_line(line, acc) do
    case parse_property(line) do
      {"FN", _params, value} ->
        %{acc | display_name: unescape(value)}

      {"N", _params, value} ->
        parts = String.split(value, ";", parts: 5)
        last = Enum.at(parts, 0) |> unescape_or_nil()
        first = Enum.at(parts, 1) |> unescape_or_nil()
        %{acc | last_name: last, first_name: first}

      {"NICKNAME", _params, value} ->
        %{acc | nickname: unescape(value)}

      {"BDAY", _params, value} ->
        %{acc | birthdate: parse_date(value)}

      {"ORG", _params, value} ->
        # ORG can have sub-components separated by ;
        company = value |> String.split(";") |> List.first() |> unescape()
        %{acc | company: company}

      {"TITLE", _params, value} ->
        %{acc | occupation: unescape(value)}

      {"NOTE", _params, value} ->
        %{acc | description: unescape(value)}

      {"TEL", params, value} ->
        label = extract_type(params)
        %{acc | phones: acc.phones ++ [%{value: unescape(value), label: label}]}

      {"EMAIL", params, value} ->
        label = extract_type(params)
        %{acc | emails: acc.emails ++ [%{value: unescape(value), label: label}]}

      {"ADR", params, value} ->
        label = extract_type(params)
        addr = parse_address(value, label)
        %{acc | addresses: acc.addresses ++ [addr]}

      {"URL", params, value} ->
        label = extract_type(params)
        %{acc | urls: acc.urls ++ [%{value: unescape(value), label: label}]}

      {"IMPP", params, value} ->
        label = extract_type(params)
        %{acc | urls: acc.urls ++ [%{value: unescape(value), label: label}]}

      {name, params, value} when name in ["X-SOCIALPROFILE", "X-TWITTER", "X-INSTAGRAM"] ->
        label = extract_type(params) || social_label(name)
        %{acc | urls: acc.urls ++ [%{value: unescape(value), label: label}]}

      _ ->
        acc
    end
  end

  # ── Property Parsing ───────────────────────────────────────────────────

  defp parse_property(line) do
    case String.split(line, ":", parts: 2) do
      [name_and_params, value] ->
        {name, params} = parse_name_params(name_and_params)
        {String.upcase(name), params, value}

      _ ->
        nil
    end
  end

  defp parse_name_params(str) do
    case String.split(str, ";", parts: 2) do
      [name] -> {name, %{}}
      [name, params_str] -> {name, parse_params(params_str)}
    end
  end

  defp parse_params(str) do
    str
    |> String.split(";")
    |> Enum.reduce(%{}, fn param, acc ->
      case String.split(param, "=", parts: 2) do
        [key, value] -> Map.put(acc, String.upcase(key), value)
        # Bare parameter (vCard 2.1 style): e.g., TEL;CELL:...
        [bare] -> Map.put(acc, "TYPE", bare)
      end
    end)
  end

  # ── Address Parsing ────────────────────────────────────────────────────

  defp parse_address(value, label) do
    parts = String.split(value, ";", parts: 7)

    %{
      label: label,
      line2: Enum.at(parts, 1) |> unescape_or_nil(),
      line1: Enum.at(parts, 2) |> unescape_or_nil(),
      city: Enum.at(parts, 3) |> unescape_or_nil(),
      province: Enum.at(parts, 4) |> unescape_or_nil(),
      postal_code: Enum.at(parts, 5) |> unescape_or_nil(),
      country: Enum.at(parts, 6) |> unescape_or_nil()
    }
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp extract_type(params) do
    case Map.get(params, "TYPE") do
      nil -> nil
      type -> type |> String.split(",") |> List.first() |> String.downcase() |> label_name()
    end
  end

  defp label_name("home"), do: "Home"
  defp label_name("work"), do: "Work"
  defp label_name("cell"), do: "Cell"
  defp label_name("fax"), do: "Fax"
  defp label_name("pref"), do: nil
  defp label_name(other), do: String.capitalize(other)

  defp social_label("X-TWITTER"), do: "Twitter"
  defp social_label("X-INSTAGRAM"), do: "Instagram"
  defp social_label(_), do: nil

  defp parse_date(str) do
    str = String.trim(str)

    cond do
      # ISO 8601: 1990-06-15
      String.match?(str, ~r/^\d{4}-\d{2}-\d{2}$/) ->
        case Date.from_iso8601(str) do
          {:ok, date} -> date
          _ -> nil
        end

      # Compact: 19900615
      String.match?(str, ~r/^\d{8}$/) ->
        compact =
          String.slice(str, 0, 4) <>
            "-" <> String.slice(str, 4, 2) <> "-" <> String.slice(str, 6, 2)

        case Date.from_iso8601(compact) do
          {:ok, date} -> date
          _ -> nil
        end

      # vCard 4.0 with dashes but no year: --0615
      String.match?(str, ~r/^--\d{4}$/) ->
        nil

      true ->
        nil
    end
  end

  @doc """
  Unescapes vCard property values.
  """
  def unescape(nil), do: nil

  def unescape(value) do
    value
    |> String.replace("\\n", "\n")
    |> String.replace("\\N", "\n")
    |> String.replace("\\;", ";")
    |> String.replace("\\,", ",")
    |> String.replace("\\\\", "\\")
  end

  defp unescape_or_nil(nil), do: nil
  defp unescape_or_nil(""), do: nil
  defp unescape_or_nil(str), do: unescape(str)
end
