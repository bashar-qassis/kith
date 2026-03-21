defmodule Kith.Workers.PhotoSyncWorker do
  use Oban.Worker, queue: :photo_sync, max_attempts: 3

  require Logger

  alias Kith.Imports
  alias Kith.Contacts.Photo
  alias Kith.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
    args: %{"import_id" => import_id, "photo_id" => photo_id, "source_photo_id" => source_photo_id},
    attempt: attempt,
    max_attempts: max_attempts
  }) do
    with {:import, %{} = import} <- {:import, Imports.get_import(import_id)},
         {:photo, %Photo{} = photo} <- {:photo, Repo.get(Photo, photo_id)},
         {:source, {:ok, source_mod}} <- {:source, Imports.resolve_source(import.source)} do

      if import.status == "cancelled", do: throw(:cancelled)

      case Kith.Storage.check_storage_limit(import.account_id, 0) do
        :ok -> :ok
        {:error, _} ->
          Logger.warning("Storage limit reached for account #{import.account_id}, discarding photo #{photo_id}")
          Repo.delete(photo)
          throw(:discard)
      end

      credential = %{url: import.api_url, api_key: import.api_key_encrypted}

      case source_mod.fetch_photo(credential, source_photo_id) do
        {:ok, binary} ->
          storage_key = Kith.Storage.generate_key(import.account_id, "photos", photo.file_name)
          {:ok, _} = Kith.Storage.upload_binary(binary, storage_key)

          photo
          |> Ecto.Changeset.change(%{storage_key: storage_key, file_size: byte_size(binary)})
          |> Repo.update!()

          maybe_cleanup_api_key(import)
          :ok

        {:error, :rate_limited} ->
          {:snooze, 60}

        {:error, reason} ->
          Logger.warning("Photo sync failed for #{source_photo_id}: #{inspect(reason)}")
          # On final attempt: delete broken Photo record
          if attempt >= max_attempts do
            Repo.delete(photo)
            Logger.warning("Deleted photo #{photo_id} after #{max_attempts} failed attempts")
          end
          {:error, reason}
      end
    else
      {:import, nil} -> {:discard, "Import not found"}
      {:photo, nil} -> {:discard, "Photo not found"}
      {:source, {:error, _}} -> {:discard, "Unknown source"}
    end
  catch
    :cancelled -> {:discard, "Import cancelled"}
    :discard -> {:discard, "Storage limit reached"}
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  defp maybe_cleanup_api_key(import) do
    if Imports.pending_async_jobs_count(import.id) <= 1 do
      Imports.wipe_api_key(import)
    end
  end
end
