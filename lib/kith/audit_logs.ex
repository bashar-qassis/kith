defmodule Kith.AuditLogs do
  @moduledoc """
  The AuditLogs context — tracks user actions for auditing purposes.
  """

  import Ecto.Query, warn: false
  import Kith.Scope

  alias Kith.Repo
  alias Kith.AuditLogs.AuditLog

  def list_audit_logs(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    AuditLog
    |> scope_to_account(account_id)
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def list_audit_logs_for_contact(account_id, contact_id) do
    AuditLog
    |> scope_to_account(account_id)
    |> where([l], l.contact_id == ^contact_id)
    |> order_by([l], desc: l.inserted_at)
    |> Repo.all()
  end

  def create_audit_log(account_id, attrs) do
    %AuditLog{}
    |> AuditLog.create_changeset(Map.put(attrs, :account_id, account_id))
    |> Repo.insert()
  end

  def log_event(account_id, user, event, opts \\ []) do
    attrs = %{
      user_id: user.id,
      user_name: Map.get(user, :display_name) || user.email,
      event: event,
      contact_id: Keyword.get(opts, :contact_id),
      contact_name: Keyword.get(opts, :contact_name),
      metadata: Keyword.get(opts, :metadata)
    }

    create_audit_log(account_id, attrs)
  end
end
