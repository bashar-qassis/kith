defmodule Kith.Workers.ImportFileCleanupWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  import Ecto.Query
  alias Kith.Repo
  alias Kith.Imports.Import

  @retention_days 30

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@retention_days * 86_400, :second)

    imports =
      Import
      |> where([i], i.status in ["completed", "failed", "cancelled"])
      |> where([i], not is_nil(i.file_storage_key))
      |> where(
        [i],
        i.completed_at < ^cutoff or (is_nil(i.completed_at) and i.updated_at < ^cutoff)
      )
      |> Repo.all()

    Enum.each(imports, fn import ->
      case Kith.Storage.delete(import.file_storage_key) do
        :ok ->
          import
          |> Ecto.Changeset.change(file_storage_key: nil)
          |> Repo.update!()

          Logger.info("Cleaned up import file for import #{import.id}")

        {:error, reason} ->
          Logger.warning(
            "Failed to delete import file #{import.file_storage_key}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
