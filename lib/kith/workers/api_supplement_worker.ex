defmodule Kith.Workers.ApiSupplementWorker do
  use Oban.Worker, queue: :api_supplement, max_attempts: 3

  require Logger

  alias Kith.Imports
  alias Kith.Contacts.Contact
  alias Kith.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "import_id" => import_id,
          "contact_id" => contact_id,
          "source_contact_id" => source_contact_id,
          "key" => key
        }
      }) do
    with {:import, %{} = import} <- {:import, Imports.get_import(import_id)},
         {:contact, %Contact{} = contact} <- {:contact, Repo.get(Contact, contact_id)},
         {:source, {:ok, source_mod}} <- {:source, Imports.resolve_source(import.source)},
         {:key, {:ok, key_atom}} <- {:key, safe_to_atom(key)} do
      if import.status == "cancelled", do: throw(:cancelled)

      credential = %{url: import.api_url, api_key: import.api_key_encrypted}

      case source_mod.fetch_supplement(credential, source_contact_id, key_atom) do
        {:ok, data} ->
          attrs = Map.take(data, [:first_met_where, :first_met_additional_info])
          Kith.Contacts.update_contact(contact, attrs)
          maybe_cleanup_api_key(import)
          :ok

        {:error, :rate_limited} ->
          {:snooze, 60}

        {:error, reason} ->
          Logger.warning(
            "API supplement failed for contact #{source_contact_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      {:import, nil} -> {:discard, "Import not found"}
      {:contact, nil} -> {:discard, "Contact not found"}
      {:source, {:error, _}} -> {:discard, "Unknown source"}
      {:key, {:error, _}} -> {:discard, "Unknown supplement key"}
    end
  catch
    :cancelled -> {:discard, "Import cancelled"}
  end

  defp safe_to_atom(str) do
    {:ok, String.to_existing_atom(str)}
  rescue
    ArgumentError -> {:error, :unknown_atom}
  end

  defp maybe_cleanup_api_key(import) do
    if Imports.pending_async_jobs_count(import.id) <= 1 do
      Imports.wipe_api_key(import)
    end
  end
end
