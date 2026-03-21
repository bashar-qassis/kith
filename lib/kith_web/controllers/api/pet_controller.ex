defmodule KithWeb.API.PetController do
  use KithWeb, :controller

  alias Kith.{Contacts, Policy, Repo}
  alias Kith.Contacts.Pet
  alias Kith.Scope, as: TenantScope
  alias KithWeb.API.Pagination

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  # ── List pets for a contact ──────────────────────────────────────────

  def index(conn, %{"contact_id" => contact_id} = params) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id

    with {:ok, _contact} <- fetch_contact(account_id, contact_id) do
      query =
        Pet
        |> TenantScope.scope_to_account(account_id)
        |> where([p], p.contact_id == ^contact_id)

      {pets, meta} = Pagination.paginate(query, params)
      json(conn, Pagination.paginated_response(Enum.map(pets, &pet_json/1), meta))
    end
  end

  # ── Show pet ─────────────────────────────────────────────────────────

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id

    case Pet |> TenantScope.scope_to_account(account_id) |> Repo.get(id) do
      nil -> {:error, :not_found}
      pet -> json(conn, %{data: pet_json(pet)})
    end
  end

  # ── Create pet ───────────────────────────────────────────────────────

  def create(conn, %{"contact_id" => contact_id, "pet" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :create, :pet),
         {:ok, contact} <- fetch_contact(account_id, contact_id),
         {:ok, pet} <-
           %Pet{contact_id: contact.id, account_id: account_id}
           |> Pet.changeset(attrs)
           |> Repo.insert() do
      conn
      |> put_status(201)
      |> put_resp_header("location", "/api/pets/#{pet.id}")
      |> json(%{data: pet_json(pet)})
    else
      false -> {:error, :forbidden}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def create(_conn, %{"contact_id" => _contact_id}) do
    {:error, :bad_request, "Missing 'pet' key in request body."}
  end

  # ── Update pet ───────────────────────────────────────────────────────

  def update(conn, %{"id" => id, "pet" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :pet),
         pet when not is_nil(pet) <-
           Pet |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, updated} <- pet |> Pet.changeset(attrs) |> Repo.update() do
      json(conn, %{data: pet_json(updated)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def update(_conn, %{"id" => _id}) do
    {:error, :bad_request, "Missing 'pet' key in request body."}
  end

  # ── Delete pet ───────────────────────────────────────────────────────

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :delete, :pet),
         pet when not is_nil(pet) <-
           Pet |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, _pet} <- Repo.delete(pet) do
      send_resp(conn, 204, "")
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp fetch_contact(account_id, contact_id) do
    case Contacts.get_contact(account_id, contact_id) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  defp pet_json(%Pet{} = pet) do
    %{
      id: pet.id,
      contact_id: pet.contact_id,
      name: pet.name,
      species: pet.species,
      breed: pet.breed,
      date_of_birth: pet.date_of_birth,
      date_of_death: pet.date_of_death,
      notes: pet.notes,
      is_private: pet.is_private,
      inserted_at: pet.inserted_at,
      updated_at: pet.updated_at
    }
  end
end
