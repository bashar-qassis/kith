defmodule Kith.Workers.AccountDeletionWorker do
  @moduledoc """
  Oban worker that performs full account deletion.

  Sessions are already invalidated synchronously before this job is enqueued.
  This worker handles the data cleanup: files, Oban jobs, then the account
  record (CASCADE deletes everything else).
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 300, fields: [:args], keys: [:account_id]]

  import Ecto.Query
  alias Kith.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    # Verify account still exists (race condition guard)
    case Repo.get(Kith.Accounts.Account, account_id) do
      nil ->
        Logger.info("AccountDeletionWorker: account #{account_id} already deleted, skipping")
        :ok

      account ->
        Logger.info("AccountDeletionWorker: starting deletion for account #{account_id}")

        # 1. Cancel all Oban reminder jobs
        cancel_reminder_jobs(account_id)

        # 2. Delete stored files
        delete_stored_files(account_id)

        # 3. Delete all user tokens (sessions already cleared, but ensure clean)
        user_ids =
          from(u in Kith.Accounts.User, where: u.account_id == ^account_id, select: u.id)
          |> Repo.all()

        from(t in Kith.Accounts.UserToken, where: t.user_id in ^user_ids)
        |> Repo.delete_all()

        # 4. Delete users
        from(u in Kith.Accounts.User, where: u.account_id == ^account_id)
        |> Repo.delete_all()

        # 5. Delete account (CASCADE handles remaining tables)
        Repo.delete(account)

        Logger.info("AccountDeletionWorker: completed deletion for account #{account_id}")
        :ok
    end
  end

  defp cancel_reminder_jobs(account_id) do
    job_ids =
      from(r in Kith.Reminders.Reminder,
        where: r.account_id == ^account_id,
        select: r.enqueued_oban_job_ids
      )
      |> Repo.all()
      |> List.flatten()

    Enum.each(job_ids, &Oban.cancel_job/1)
  end

  defp delete_stored_files(account_id) do
    # Delete photo files
    from(p in Kith.Contacts.Photo,
      join: c in Kith.Contacts.Contact,
      on: p.contact_id == c.id,
      where: c.account_id == ^account_id,
      select: p.storage_key
    )
    |> Repo.all()
    |> Enum.each(&safe_delete_file/1)

    # Delete document files
    from(d in Kith.Contacts.Document,
      join: c in Kith.Contacts.Contact,
      on: d.contact_id == c.id,
      where: c.account_id == ^account_id,
      select: d.storage_key
    )
    |> Repo.all()
    |> Enum.each(&safe_delete_file/1)
  end

  defp safe_delete_file(nil), do: :ok

  defp safe_delete_file(key) do
    case Kith.Storage.delete(key) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Failed to delete file #{key}: #{inspect(reason)}")
    end
  end
end
