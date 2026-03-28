defmodule Kith.Workers.PhotoBatchSyncWorker do
  @moduledoc """
  Batch Oban worker that syncs all pending photos for an import in a single job.

  Paginates through the source API's photo list, matches pending photos by UUID,
  decodes the dataUrl, and uploads to local storage. Idempotent on retry —
  already-synced photos are skipped.
  """

  use Oban.Worker, queue: :photo_sync, max_attempts: 3

  require Logger

  alias Kith.Contacts.Photo
  alias Kith.Imports
  alias Kith.Imports.Import
  alias Kith.Repo

  @max_pages 50

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_id" => import_id}}) do
    case Imports.get_import(import_id) do
      nil ->
        {:discard, "Import not found"}

      %Import{status: "cancelled"} ->
        {:discard, "Import cancelled"}

      %Import{} = import ->
        run_sync(import)
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp run_sync(import) do
    case Imports.resolve_source(import.source) do
      {:ok, source_mod} ->
        pending = load_pending_photos(import.id)

        if map_size(pending) == 0 do
          Logger.info("Import #{import.id}: no pending photos to sync")
          save_sync_summary(import, %{synced: [], failed: [], not_found: []})
          maybe_cleanup_api_key(import)
          :ok
        else
          credential = %{url: import.api_url, api_key: import.api_key_encrypted}
          results = %{synced: [], failed: [], not_found: []}
          do_sync(source_mod, credential, import, pending, results)
        end

      {:error, _} ->
        {:discard, "Unknown source"}
    end
  end

  defp load_pending_photos(import_id) do
    Imports.list_import_records(import_id)
    |> Enum.filter(&(&1.source_entity_type == "photo"))
    |> Enum.reduce(%{}, fn rec, acc ->
      maybe_add_pending_photo(rec, acc)
    end)
  end

  defp maybe_add_pending_photo(rec, acc) do
    case Repo.get(Photo, rec.local_entity_id) |> Repo.preload(:contact) do
      %Photo{} = photo ->
        if Photo.pending_sync?(photo),
          do: Map.put(acc, rec.source_entity_id, photo),
          else: acc

      nil ->
        acc
    end
  end

  defp do_sync(source_mod, credential, import, pending, results) do
    case paginate_and_sync(source_mod, credential, import, pending, results, 1) do
      {:ok, final_pending, final_results} ->
        final_results = cleanup_unresolved(final_pending, final_results)
        save_sync_summary(import, final_results)
        maybe_cleanup_api_key(import)
        :ok

      {:error, reason} ->
        save_sync_summary(import, results)
        {:error, reason}
    end
  end

  defp paginate_and_sync(_source_mod, _cred, _import, pending, results, page)
       when page > @max_pages do
    {:ok, pending, results}
  end

  defp paginate_and_sync(_source_mod, _cred, _import, pending, results, _page)
       when map_size(pending) == 0 do
    {:ok, pending, results}
  end

  defp paginate_and_sync(source_mod, credential, import, pending, results, page) do
    case source_mod.list_photos(credential, page) do
      {:ok, []} ->
        {:ok, pending, results}

      {:ok, photos} ->
        {remaining, updated_results} = process_page(photos, pending, import, results)
        paginate_and_sync(source_mod, credential, import, remaining, updated_results, page + 1)

      {:error, :rate_limited} ->
        Logger.info("Import #{import.id}: rate limited on page #{page}, waiting 65s")
        Process.sleep(:timer.seconds(65))
        paginate_and_sync(source_mod, credential, import, pending, results, page)

      {:error, reason} ->
        Logger.warning("Import #{import.id}: API error on page #{page}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_page(api_photos, pending, import, results) do
    Enum.reduce(api_photos, {pending, results}, fn api_photo, {pending_acc, results_acc} ->
      uuid = api_photo["uuid"]

      case Map.get(pending_acc, uuid) do
        nil ->
          {pending_acc, results_acc}

        photo ->
          {status, reason} = sync_single_photo(api_photo, photo, import, uuid)
          entry = build_result_entry(photo, uuid, status, reason)
          updated_results = Map.update!(results_acc, status, &[entry | &1])
          {Map.delete(pending_acc, uuid), updated_results}
      end
    end)
  end

  defp sync_single_photo(api_photo, photo, import, uuid) do
    with data_url when is_binary(data_url) and data_url != "" <- api_photo["dataUrl"],
         {:ok, binary} <- decode_data_url(data_url),
         content_hash <- :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower),
         false <- Kith.Contacts.photo_exists_by_hash?(photo.contact_id, content_hash),
         :ok <- check_storage_limit(import, photo),
         storage_key <- Kith.Storage.generate_key(import.account_id, "photos", photo.file_name),
         {:ok, _} <- Kith.Storage.upload_binary(binary, storage_key) do
      updated_photo =
        photo
        |> Ecto.Changeset.change(%{
          storage_key: storage_key,
          file_size: byte_size(binary),
          content_hash: content_hash
        })
        |> Repo.update!()

      # Set as avatar if contact doesn't have one yet
      contact = Repo.get!(Kith.Contacts.Contact, photo.contact_id)

      if is_nil(contact.avatar) do
        Kith.Contacts.set_avatar(contact, updated_photo)
      end

      Logger.info("Synced photo #{photo.id} (#{uuid})")
      {:synced, nil}
    else
      true ->
        Logger.info("Photo #{uuid}: duplicate content, removing pending record")
        Repo.delete(photo)
        {:synced, "duplicate skipped"}

      nil ->
        Logger.warning("Photo #{uuid}: dataUrl is empty")
        Repo.delete(photo)
        {:failed, "dataUrl empty"}

      :error ->
        Logger.warning("Photo #{uuid}: dataUrl decode failed")
        Repo.delete(photo)
        {:failed, "decode failed"}

      {:error, reason} ->
        Logger.warning("Photo #{uuid}: #{inspect(reason)}")
        Repo.delete(photo)
        {:failed, inspect(reason)}
    end
  end

  defp cleanup_unresolved(pending, results) when map_size(pending) == 0, do: results

  defp cleanup_unresolved(pending, results) do
    not_found_entries =
      Enum.map(pending, fn {uuid, photo} ->
        Repo.delete(photo)
        Logger.warning("Deleted unresolved photo #{photo.id} (#{uuid})")
        build_result_entry(photo, uuid, :not_found, "not found on source")
      end)

    Map.update!(results, :not_found, &(not_found_entries ++ &1))
  end

  defp build_result_entry(photo, uuid, status, reason) do
    entry = %{
      "uuid" => uuid,
      "file_name" => photo.file_name,
      "status" => to_string(status),
      "contact_id" => photo.contact_id
    }

    if reason, do: Map.put(entry, "reason", reason), else: entry
  end

  defp save_sync_summary(import, results) do
    all_photos = results.synced ++ results.failed ++ results.not_found

    summary = %{
      "status" => "completed",
      "total" => length(all_photos),
      "synced" => length(results.synced),
      "failed" => length(results.failed),
      "not_found" => length(results.not_found),
      "photos" => all_photos
    }

    Imports.update_sync_summary(import, summary)

    topic = "import:#{import.account_id}"
    Phoenix.PubSub.broadcast(Kith.PubSub, topic, {:sync_complete, summary})
  end

  defp decode_data_url("data:" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [_meta, encoded] ->
        case Base.decode64(encoded) do
          {:ok, binary} -> {:ok, binary}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp decode_data_url(_), do: :error

  defp check_storage_limit(import, _photo) do
    case Kith.Storage.check_storage_limit(import.account_id, 0) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  defp maybe_cleanup_api_key(import) do
    if Imports.pending_async_jobs_count(import.id) <= 1 do
      Imports.wipe_api_key(import)
    end
  end
end
