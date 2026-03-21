defmodule Kith.Imports.Sources.VCard do
  @behaviour Kith.Imports.Source

  alias Kith.VCard.Parser
  alias Kith.Contacts
  alias Kith.Imports

  require Logger

  @impl true
  def name, do: "vCard"

  @impl true
  def file_types, do: [".vcf"]

  @impl true
  def supports_api?, do: false

  @impl true
  def validate_file(data) do
    if String.contains?(data, "BEGIN:VCARD") do
      {:ok, %{}}
    else
      {:error, "File does not appear to be a valid vCard file"}
    end
  end

  @impl true
  def parse_summary(data) do
    case Parser.parse(data) do
      {:ok, contacts} -> {:ok, %{contacts: length(contacts)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def import(account_id, _user_id, data, opts) do
    import_record = opts[:import]

    case Parser.parse(data) do
      {:ok, parsed_contacts} ->
        total = length(parsed_contacts)
        topic = "import:#{account_id}"
        broadcast_interval = max(1, div(total, 50))

        result =
          parsed_contacts
          |> Enum.with_index(1)
          |> Enum.reduce(%{contacts: 0, notes: 0, skipped: 0, error_count: 0, errors: []}, fn {parsed, idx}, acc ->
            if import_record && rem(idx, 10) == 0 do
              refreshed = Imports.get_import!(import_record.id)
              if refreshed.status == "cancelled", do: throw(:cancelled)
            end

            result =
              try do
                case Contacts.import_contact(account_id, parsed) do
                  {:ok, contact} ->
                    if import_record do
                      source_id = "vcard-#{idx}"
                      Imports.record_imported_entity(import_record, "contact", source_id, "contact", contact.id)
                    end
                    %{acc | contacts: acc.contacts + 1}

                  {:error, reason} ->
                    add_error(acc, "Contact #{idx}: #{inspect(reason)}")
                end
              rescue
                e ->
                  add_error(acc, "Contact #{idx}: #{Exception.message(e)}")
              end

            if rem(idx, broadcast_interval) == 0 || idx == total do
              Phoenix.PubSub.broadcast(Kith.PubSub, topic, {:import_progress, %{current: idx, total: total}})
            end

            result
          end)

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  catch
    :cancelled -> {:ok, %{contacts: 0, notes: 0, skipped: 0, error_count: 0, errors: ["Import cancelled"]}}
  end

  defp add_error(acc, msg) do
    errors = if length(acc.errors) < 50, do: acc.errors ++ [msg], else: acc.errors
    %{acc | skipped: acc.skipped + 1, error_count: acc.error_count + 1, errors: errors}
  end
end
