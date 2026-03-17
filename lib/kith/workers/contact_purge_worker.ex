defmodule Kith.Workers.ContactPurgeWorker do
  @moduledoc """
  Nightly cron job (3 AM UTC) that hard-deletes contacts
  where deleted_at < NOW() - 30 days. Batch limit: 500.
  Full implementation in Phase 04.
  """

  use Oban.Worker, queue: :purge

  @impl Oban.Worker
  def perform(_job) do
    # TODO: Implement in Phase 04
    :ok
  end
end
