defmodule Kith.Immich do
  @moduledoc """
  Top-level module for Immich integration.
  Provides manual sync triggering and global enabled check.
  """

  @doc """
  Triggers an immediate Immich sync for an account.
  Inserts an ImmichSyncWorker job with priority 0 and 60-second uniqueness.
  Returns `{:ok, %Oban.Job{}}` or `{:error, changeset}`.
  """
  def trigger_sync(account) do
    %{account_id: account.id}
    |> Kith.Workers.ImmichSyncWorker.new(
      priority: 0,
      unique: [period: 60, fields: [:args, :queue]]
    )
    |> Oban.insert()
  end

  @doc "Returns true if Immich integration is globally enabled."
  def enabled? do
    System.get_env("IMMICH_ENABLED") == "true"
  end
end
