defmodule Kith.Reminders.Cleanup do
  @moduledoc """
  Cancels all Oban jobs tracked on the account's reminders, then deletes
  the reminders. FK CASCADE removes `reminder_rules` and `reminder_instances`.
  """

  alias Kith.Reminders.Reminder
  alias Kith.Repo

  import Ecto.Query
  require Logger

  @spec wipe_for_account(account_id :: integer()) :: :ok
  def wipe_for_account(account_id) do
    cancel_oban_jobs_for_account(account_id)

    {count, _} =
      Repo.delete_all(from(r in Reminder, where: r.account_id == ^account_id))

    Logger.info("[Reminders.Cleanup] wiped #{count} reminder(s) for account #{account_id}")
    :ok
  end

  defp cancel_oban_jobs_for_account(account_id) do
    job_ids =
      Repo.all(
        from(r in Reminder,
          where: r.account_id == ^account_id,
          select: r.enqueued_oban_job_ids
        )
      )
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    Enum.each(job_ids, &Oban.cancel_job/1)
  end
end
