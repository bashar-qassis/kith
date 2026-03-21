defmodule KithWeb.API.GenderController do
  use KithWeb, :controller

  alias Kith.{Contacts, Policy}
  alias Kith.Contacts.Gender

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  def index(conn, _params) do
    account_id = conn.assigns.current_scope.account.id

    genders =
      Gender
      |> where([g], is_nil(g.account_id) or g.account_id == ^account_id)
      |> order_by([g], asc: g.position)
      |> Kith.Repo.all()

    json(conn, %{data: Enum.map(genders, &gender_json/1)})
  end

  def create(conn, %{"gender" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :manage, :account) do
      case Contacts.create_gender(account_id, attrs) do
        {:ok, gender} -> conn |> put_status(201) |> json(%{data: gender_json(gender)})
        {:error, cs} -> {:error, cs}
      end
    else
      false -> {:error, :forbidden}
    end
  end

  def update(conn, %{"id" => id, "gender" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :manage, :account) do
      gender = Contacts.get_gender!(account_id, id)

      case Contacts.update_gender(gender, attrs) do
        {:ok, updated} -> json(conn, %{data: gender_json(updated)})
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
      gender = Contacts.get_gender!(account_id, id)

      case Contacts.delete_gender(gender) do
        {:ok, _} ->
          send_resp(conn, 204, "")

        {:error, :global_read_only} ->
          {:error, :forbidden}

        {:error, :in_use} ->
          {:error, :bad_request, "Cannot delete gender that is assigned to contacts."}

        {:error, cs} ->
          {:error, cs}
      end
    else
      false -> {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp gender_json(%Gender{} = g) do
    %{
      id: g.id,
      name: g.name,
      position: g.position,
      is_custom: not is_nil(g.account_id)
    }
  end
end
