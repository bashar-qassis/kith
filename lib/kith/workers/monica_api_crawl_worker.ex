defmodule Kith.Workers.MonicaApiCrawlWorker do
  @moduledoc """
  Oban worker that crawls a Monica CRM API instance and imports all contacts.

  Single long-running job that paginates through the contacts API, imports
  contacts with all embedded data, resolves cross-references, and optionally
  imports photos.

  Connection is validated in the import wizard before this job is enqueued.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Kith.Imports
  alias Kith.Imports.Sources.MonicaApi

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_id" => import_id}}) do
    import_job = Imports.get_import!(import_id)

    with {:ok, _} <-
           Imports.update_import_status(import_job, "processing", %{
             started_at: DateTime.utc_now()
           }),
         credential <- build_credential(import_job),
         opts <- build_opts(import_job),
         {:ok, summary} <-
           MonicaApi.crawl(
             import_job.account_id,
             import_job.user_id,
             credential,
             import_job,
             opts
           ) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      summary_map = ensure_map(summary)

      Imports.update_import_status(import_job, "completed", %{
        summary: summary_map,
        completed_at: now
      })

      Imports.wipe_api_key(import_job)

      topic = "import:#{import_job.account_id}"
      Phoenix.PubSub.broadcast(Kith.PubSub, topic, {:import_complete, summary_map})

      Logger.info("MonicaApi import #{import_id} completed: #{inspect(summary_map)}")
      :ok
    else
      {:error, reason} ->
        Logger.error("MonicaApi import #{import_id} failed: #{inspect(reason)}")

        Imports.update_import_status(import_job, "failed", %{
          summary: %{error: inspect(reason)},
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        Imports.wipe_api_key(import_job)

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp build_credential(import_job) do
    %{
      url: import_job.api_url,
      api_key: import_job.api_key_encrypted
    }
  end

  defp build_opts(import_job) do
    options = import_job.api_options || %{}

    %{
      "photos" => options["photos"] || false,
      "extra_notes" => options["extra_notes"] != false
    }
  end

  defp ensure_map(m) when is_map(m), do: m
end
