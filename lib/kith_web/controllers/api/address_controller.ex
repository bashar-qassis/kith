defmodule KithWeb.API.AddressController do
  @moduledoc """
  REST API controller for contact addresses.
  """

  use KithWeb, :controller

  alias Kith.{Contacts, Policy, Repo}
  alias Kith.Contacts.Address
  alias Kith.Scope, as: TenantScope
  alias KithWeb.API.Pagination

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  # ── List addresses for a contact ─────────────────────────────────────

  def index(conn, %{"contact_id" => contact_id} = params) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id

    with {:ok, _contact} <- fetch_contact(account_id, contact_id) do
      query =
        Address
        |> TenantScope.scope_to_account(account_id)
        |> where([a], a.contact_id == ^contact_id)

      {addresses, meta} = Pagination.paginate(query, params)
      json(conn, Pagination.paginated_response(Enum.map(addresses, &address_json/1), meta))
    end
  end

  # ── Create address ───────────────────────────────────────────────────

  def create(conn, %{"contact_id" => contact_id, "address" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :create, :address),
         {:ok, contact} <- fetch_contact(account_id, contact_id),
         {:ok, address} <- Contacts.create_address(contact, account_id, attrs) do
      conn
      |> put_status(201)
      |> put_resp_header("location", "/api/addresses/#{address.id}")
      |> json(%{data: address_json(address)})
    else
      false -> {:error, :forbidden}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def create(_conn, %{"contact_id" => _contact_id}) do
    {:error, :bad_request, "Missing 'address' key in request body."}
  end

  # ── Update address ───────────────────────────────────────────────────

  def update(conn, %{"id" => id, "address" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :address),
         address when not is_nil(address) <-
           Address |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, updated} <- Contacts.update_address(address, attrs) do
      json(conn, %{data: address_json(updated)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def update(_conn, %{"id" => _id}) do
    {:error, :bad_request, "Missing 'address' key in request body."}
  end

  # ── Delete address ───────────────────────────────────────────────────

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :delete, :address),
         address when not is_nil(address) <-
           Address |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, _address} <- Contacts.delete_address(address) do
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

  defp address_json(address) do
    %{
      id: address.id,
      contact_id: address.contact_id,
      label: address.label,
      line1: address.line1,
      line2: address.line2,
      city: address.city,
      province: address.province,
      postal_code: address.postal_code,
      country: address.country,
      latitude: address.latitude,
      longitude: address.longitude,
      inserted_at: address.inserted_at,
      updated_at: address.updated_at
    }
  end
end
