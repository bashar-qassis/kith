defmodule Kith.Workers.ImportSourceWorker do
  @moduledoc """
  Generic Oban worker that orchestrates any import source.
  Loads the import job, resolves the source module, loads the file from
  Storage, and delegates to `source.import/4`.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Kith.Imports
  alias Kith.Imports.Sources.Monica
  alias Kith.Storage
  alias Kith.Workers.ApiSupplementWorker
  alias Kith.Workers.PhotoBatchSyncWorker

  @dialyzer {:nowarn_function, maybe_enqueue_first_met_jobs: 2}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_id" => import_id}}) do
    import = Imports.get_import!(import_id)

    with {:ok, source_mod} <- Imports.resolve_source(import.source),
         {:ok, _} <-
           Imports.update_import_status(import, "processing", %{started_at: DateTime.utc_now()}),
         {:ok, data} <- load_file(import.file_storage_key),
         {:ok, summary} <-
           source_mod.import(import.account_id, import.user_id, data, %{import: import}) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      summary_map = ensure_map(summary)

      Imports.update_import_status(import, "completed", %{
        summary: summary_map,
        completed_at: now
      })

      if import.api_url && import.api_key_encrypted && import.api_options do
        enqueue_async_jobs(import)
      else
        Logger.info(
          "Import #{import_id}: skipping async jobs (api_url=#{inspect(!!import.api_url)}, api_key=#{inspect(!!import.api_key_encrypted)}, api_options=#{inspect(import.api_options)})"
        )
      end

      topic = "import:#{import.account_id}"
      Phoenix.PubSub.broadcast(Kith.PubSub, topic, {:import_complete, summary_map})

      Logger.info("Import #{import_id} completed: #{inspect(summary_map)}")
      :ok
    else
      {:error, reason} ->
        Logger.error("Import #{import_id} failed: #{inspect(reason)}")

        Imports.update_import_status(import, "failed", %{
          summary: %{error: inspect(reason)},
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        {:error, reason}
    end
  end

  defp load_file(nil), do: {:error, "No file storage key"}

  defp load_file(key) do
    case Storage.read(key) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, "Failed to load file: #{inspect(reason)}"}
    end
  end

  defp ensure_map(%{__struct__: _} = s), do: Map.from_struct(s)
  defp ensure_map(m) when is_map(m), do: m

  defp enqueue_async_jobs(import) do
    import_records = Imports.list_import_records(import.id)

    Logger.info(
      "Import #{import.id}: #{length(import_records)} import records, api_options=#{inspect(import.api_options)}"
    )

    maybe_enqueue_photo_sync_job(import)
    maybe_enqueue_first_met_jobs(import, import_records)
  end

  defp maybe_enqueue_photo_sync_job(import) do
    if import.api_options["photos"] || import.api_options[:photos] do
      Logger.info("Import #{import.id}: enqueuing batch photo sync job")

      %{import_id: import.id}
      |> PhotoBatchSyncWorker.new()
      |> Oban.insert()
    end
  end

  defp maybe_enqueue_first_met_jobs(import, import_records) do
    if import.api_options["first_met_details"] || import.api_options[:first_met_details] do
      contacts_with_first_met = extract_first_met_uuids(import)

      contact_records =
        Enum.filter(import_records, fn rec ->
          rec.source_entity_type == "contact" and
            MapSet.member?(contacts_with_first_met, rec.source_entity_id)
        end)

      enqueue_batched_jobs(contact_records, fn rec, delay ->
        %{
          import_id: import.id,
          contact_id: rec.local_entity_id,
          source_contact_id: rec.source_entity_id,
          key: "first_met_details"
        }
        |> ApiSupplementWorker.new(scheduled_at: DateTime.add(DateTime.utc_now(), delay, :second))
        |> Oban.insert()
      end)
    end
  end

  defp extract_first_met_uuids(import) do
    with {:ok, data} <- Storage.read(import.file_storage_key),
         {:ok, parsed} <- Jason.decode(data) do
      Monica.contacts_from_parsed(parsed)
      |> Enum.filter(fn c -> get_in(c, ["first_met_date", "data", "date"]) != nil end)
      |> Enum.map(& &1["uuid"])
      |> MapSet.new()
    else
      _ -> MapSet.new()
    end
  end

  defp enqueue_batched_jobs(records, enqueue_fn) do
    records
    |> Enum.with_index()
    |> Enum.each(fn {rec, idx} ->
      delay = div(idx, 50) * 60
      enqueue_fn.(rec, delay)
    end)
  end
end
