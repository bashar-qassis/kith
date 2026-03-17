defmodule Kith.Workers.ReminderSchedulerWorker do
  @moduledoc """
  Nightly cron job (2 AM UTC) that schedules reminder notification jobs.
  Full implementation in Phase 06.
  """

  use Oban.Worker, queue: :reminders

  @impl Oban.Worker
  def perform(_job) do
    # TODO: Implement in Phase 06
    :ok
  end
end
