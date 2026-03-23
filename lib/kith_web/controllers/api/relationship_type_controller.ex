defmodule KithWeb.API.RelationshipTypeController do
  use KithWeb, :controller

  alias Kith.Contacts
  alias Kith.Contacts.RelationshipType
  alias Kith.{Policy, Repo}

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  def index(conn, _params) do
    account_id = conn.assigns.current_scope.account.id

    types =
      RelationshipType
      |> where([rt], is_nil(rt.account_id) or rt.account_id == ^account_id)
      |> order_by([rt], asc: rt.name)
      |> Repo.all()

    json(conn, %{data: Enum.map(types, &type_json/1)})
  end

  def create(conn, %{"relationship_type" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :manage, :account) do
      true ->
        case Contacts.create_relationship_type(account_id, attrs) do
          {:ok, rt} -> conn |> put_status(201) |> json(%{data: type_json(rt)})
          {:error, cs} -> {:error, cs}
        end

      false ->
        {:error, :forbidden}
    end
  end

  def update(conn, %{"id" => id, "relationship_type" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :manage, :account) do
      true ->
        rt = Contacts.get_relationship_type!(account_id, id)

        case Contacts.update_relationship_type(rt, attrs) do
          {:ok, updated} -> json(conn, %{data: type_json(updated)})
          {:error, :global_read_only} -> {:error, :forbidden}
          {:error, cs} -> {:error, cs}
        end

      false ->
        {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :manage, :account) do
      true ->
        rt = Contacts.get_relationship_type!(account_id, id)

        case Contacts.delete_relationship_type(rt) do
          {:ok, _} ->
            send_resp(conn, 204, "")

          {:error, :in_use} ->
            {:error, :bad_request, "Cannot delete relationship type that is in use."}

          {:error, cs} ->
            {:error, cs}
        end

      false ->
        {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp type_json(%RelationshipType{} = rt) do
    %{id: rt.id, name: rt.name, reverse_name: rt.reverse_name}
  end
end
