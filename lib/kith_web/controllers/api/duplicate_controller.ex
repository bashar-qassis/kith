defmodule KithWeb.API.DuplicateController do
  use KithWeb, :controller

  alias Kith.Contacts.DuplicateCandidate
  alias Kith.{DuplicateDetection, Policy}
  alias Kith.Repo
  alias Kith.Scope, as: TenantScope
  alias Kith.Workers.DuplicateDetectionWorker
  alias KithWeb.API.Pagination

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  def index(conn, params) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id

    query =
      DuplicateCandidate
      |> TenantScope.scope_to_account(account_id)
      |> where([d], d.status == "pending")
      |> order_by([d], desc: d.score)
      |> preload([:contact, :duplicate_contact])

    {candidates, meta} = Pagination.paginate(query, params)
    json(conn, Pagination.paginated_response(Enum.map(candidates, &candidate_json/1), meta))
  end

  def dismiss(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :duplicate_candidate),
         candidate when not is_nil(candidate) <-
           DuplicateCandidate |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, updated} <- DuplicateDetection.dismiss_candidate(candidate) do
      json(conn, %{
        data: candidate_json(updated |> Repo.preload([:contact, :duplicate_contact]))
      })
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def scan(conn, _params) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :manage, :account) do
      true ->
        Oban.insert(DuplicateDetectionWorker.new(%{account_id: account_id}))
        json(conn, %{status: "scanning"})

      false ->
        {:error, :forbidden}
    end
  end

  defp candidate_json(candidate) do
    %{
      id: candidate.id,
      score: candidate.score,
      reasons: candidate.reasons,
      status: candidate.status,
      detected_at: candidate.detected_at,
      resolved_at: candidate.resolved_at,
      contact: contact_summary(candidate.contact),
      duplicate_contact: contact_summary(candidate.duplicate_contact),
      inserted_at: candidate.inserted_at,
      updated_at: candidate.updated_at
    }
  end

  defp contact_summary(%Ecto.Association.NotLoaded{}), do: nil
  defp contact_summary(nil), do: nil

  defp contact_summary(contact) do
    %{
      id: contact.id,
      display_name: contact.display_name,
      first_name: contact.first_name,
      last_name: contact.last_name
    }
  end
end
