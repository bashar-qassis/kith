defmodule Kith.Contacts.PhoneFormatter do
  @moduledoc """
  Phone number normalization and formatting.

  Stores numbers in a normalized form internally (E.164 when possible),
  formats for display according to account preference.
  """

  @doc """
  Normalize a phone number for storage.

  Strips non-digit characters (preserving leading +), applies best-effort
  country code detection for bare numbers.

  Returns `{:ok, normalized}` or `{:ok, nil}` for blank input.
  """
  def normalize(nil), do: {:ok, nil}
  def normalize(""), do: {:ok, nil}

  def normalize(phone) when is_binary(phone) do
    stripped = String.trim(phone)

    has_plus = String.starts_with?(stripped, "+")
    digits = String.replace(stripped, ~r/[^\d]/, "")

    cond do
      digits == "" ->
        {:ok, nil}

      has_plus ->
        {:ok, "+" <> digits}

      # Bare 10-digit number — could be many countries, store as-is
      String.length(digits) == 10 ->
        {:ok, digits}

      # US/Canada: 11-digit starting with 1
      String.length(digits) == 11 and String.starts_with?(digits, "1") ->
        {:ok, "+" <> digits}

      # International: 7+ digits, assume needs +
      String.length(digits) >= 7 ->
        {:ok, "+" <> digits}

      # Too short to normalize meaningfully
      true ->
        {:ok, stripped}
    end
  end

  @doc """
  Format a normalized phone number for display.

  ## Formats

    * `"e164"` — E.164 as-is: `+12345678901`
    * `"national"` — US/Canada national: `(234) 567-8901`
    * `"international"` — International: `+1 234-567-8901`
    * `"raw"` — Return as-is, no formatting
  """
  def format(nil, _format), do: nil
  def format(phone, "raw"), do: phone
  def format(phone, "e164"), do: phone
  def format(phone, "national"), do: format_national(phone)
  def format(phone, "international"), do: format_international(phone)
  def format(phone, _), do: phone

  # US/Canada: +1 followed by 10 digits
  defp format_national(
         <<"+"::utf8, ?1, area::binary-size(3), prefix::binary-size(3), line::binary-size(4)>>
       )
       when byte_size(area) == 3 do
    "(#{area}) #{prefix}-#{line}"
  end

  defp format_national(phone), do: phone

  defp format_international(
         <<"+"::utf8, ?1, area::binary-size(3), prefix::binary-size(3), line::binary-size(4)>>
       )
       when byte_size(area) == 3 do
    "+1 #{area}-#{prefix}-#{line}"
  end

  defp format_international(phone), do: phone
end
