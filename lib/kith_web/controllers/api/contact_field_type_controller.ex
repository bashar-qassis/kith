defmodule KithWeb.API.ContactFieldTypeController do
  use KithWeb, :controller

  alias Kith.Contacts
  alias Kith.Contacts.ContactFieldType
  alias Kith.{Policy, Repo}

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  def index(conn, _params) do
    account_id = conn.assigns.current_scope.account.id

    types =
      ContactFieldType
      |> where([cft], is_nil(cft.account_id) or cft.account_id == ^account_id)
      |> order_by([cft], asc: cft.name)
      |> Repo.all()

    json(conn, %{data: Enum.map(types, &type_json/1)})
  end

  def create(conn, %{"contact_field_type" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :manage, :account) do
      case Contacts.create_contact_field_type(account_id, attrs) do
        {:ok, cft} -> conn |> put_status(201) |> json(%{data: type_json(cft)})
        {:error, cs} -> {:error, cs}
      end
    else
      false -> {:error, :forbidden}
    end
  end

  def update(conn, %{"id" => id, "contact_field_type" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :manage, :account) do
      cft = Contacts.get_contact_field_type!(account_id, id)

      case Contacts.update_contact_field_type(cft, attrs) do
        {:ok, updated} -> json(conn, %{data: type_json(updated)})
        {:error, :global_read_only} -> {:error, :forbidden}
        {:error, cs} -> {:error, cs}
      end
    else
      false -> {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :manage, :account) do
      cft = Contacts.get_contact_field_type!(account_id, id)

      case Contacts.delete_contact_field_type(cft) do
        {:ok, _} ->
          send_resp(conn, 204, "")

        {:error, :in_use} ->
          {:error, :bad_request, "Cannot delete contact field type that is in use."}

        {:error, cs} ->
          {:error, cs}
      end
    else
      false -> {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp type_json(%ContactFieldType{} = cft) do
    %{id: cft.id, name: cft.name, icon: cft.icon, protocol: cft.protocol}
  end
end
