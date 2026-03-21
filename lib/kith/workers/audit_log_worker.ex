defmodule Kith.Workers.AuditLogWorker do
  @moduledoc """
  Oban worker that inserts audit log rows asynchronously.

  Using Oban (not Task.start) ensures the audit log write is persisted
  in PostgreSQL and retried on failure — the entry is never lost even
  if the originating process crashes.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Kith.Repo
  alias Kith.AuditLogs.AuditLog

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %AuditLog{}
    |> AuditLog.create_changeset(args)
    |> Repo.insert()
    |> case do
      {:ok, _log} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end
end
