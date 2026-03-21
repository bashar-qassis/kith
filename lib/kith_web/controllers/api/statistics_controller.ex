defmodule KithWeb.API.StatisticsController do
  use KithWeb, :controller

  alias Kith.Repo
  alias Kith.Scope, as: TenantScope

  action_fallback KithWeb.API.FallbackController

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id
    account = scope.account

    stats = %{
      total_contacts: count(Kith.Contacts.Contact, account_id),
      total_notes: count(Kith.Contacts.Note, account_id),
      total_activities: count(Kith.Activities.Activity, account_id),
      total_calls: count(Kith.Activities.Call, account_id),
      storage_used_bytes: storage_used(account_id),
      account_created_at: account.inserted_at
    }

    json(conn, %{data: stats})
  end

  defp count(schema, account_id) do
    schema
    |> TenantScope.scope_to_account(account_id)
    |> Repo.aggregate(:count)
  end

  defp storage_used(account_id) do
    case Kith.Storage.usage(account_id) do
      {:ok, bytes} -> bytes
      _ -> 0
    end
  rescue
    _ -> 0
  end
end
