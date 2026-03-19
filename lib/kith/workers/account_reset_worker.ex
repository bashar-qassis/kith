defmodule Kith.Workers.AccountResetWorker do
  @moduledoc """
  Oban worker that resets account data — deletes all contacts and
  sub-entities while preserving users, account settings, and reference data.

  Processes in batches to avoid long-running transactions on large accounts.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 300, fields: [:args], keys: [:account_id]]

  import Ecto.Query
  alias Kith.Repo

  require Logger

  @batch_size 200

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    Logger.info("AccountResetWorker: starting reset for account #{account_id}")

    # 1. Cancel all Oban reminder jobs for the account
    cancel_reminder_jobs(account_id)

    # 2. Delete stored files (photos, documents)
    delete_stored_files(account_id)

    # 3. Delete all contacts and sub-entities in batches
    delete_contacts_in_batches(account_id)

    # 4. Delete orphaned data: tags, activities without contacts
    delete_tags(account_id)
    delete_activities(account_id)
    delete_audit_logs(account_id)

    Logger.info("AccountResetWorker: completed reset for account #{account_id}")
    :ok
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

  defp delete_contacts_in_batches(account_id) do
    # Hard-delete contacts (bypassing soft-delete) — CASCADE handles sub-entities
    contact_ids =
      from(c in Kith.Contacts.Contact,
        where: c.account_id == ^account_id,
        select: c.id,
        limit: @batch_size
      )
      |> Repo.all()

    if contact_ids != [] do
      from(c in Kith.Contacts.Contact, where: c.id in ^contact_ids)
      |> Repo.delete_all()

      delete_contacts_in_batches(account_id)
    end
  end

  defp delete_tags(account_id) do
    from(t in Kith.Contacts.Tag, where: t.account_id == ^account_id)
    |> Repo.delete_all()
  end

  defp delete_activities(account_id) do
    from(a in Kith.Activities.Activity, where: a.account_id == ^account_id)
    |> Repo.delete_all()
  end

  defp delete_audit_logs(account_id) do
    from(al in Kith.AuditLogs.AuditLog, where: al.account_id == ^account_id)
    |> Repo.delete_all()
  end
end
