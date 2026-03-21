defmodule KithWeb.API.NoteController do
  @moduledoc """
  REST API controller for contact notes.
  """

  use KithWeb, :controller

  alias Kith.{Contacts, Policy, Repo}
  alias Kith.Contacts.Note
  alias Kith.Scope, as: TenantScope
  alias KithWeb.API.Pagination

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  # ── List notes for a contact ─────────────────────────────────────────

  def index(conn, %{"contact_id" => contact_id} = params) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id

    with {:ok, _contact} <- fetch_contact(account_id, contact_id) do
      query =
        Note
        |> TenantScope.scope_to_account(account_id)
        |> where([n], n.contact_id == ^contact_id)

      {notes, meta} = Pagination.paginate(query, params)
      json(conn, Pagination.paginated_response(Enum.map(notes, &note_json/1), meta))
    end
  end

  # ── Show note ────────────────────────────────────────────────────────

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id

    case Note |> TenantScope.scope_to_account(account_id) |> Repo.get(id) do
      nil -> {:error, :not_found}
      note -> json(conn, %{data: note_json(note)})
    end
  end

  # ── Create note ──────────────────────────────────────────────────────

  def create(conn, %{"contact_id" => contact_id, "note" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :create, :note),
         {:ok, contact} <- fetch_contact(account_id, contact_id),
         {:ok, note} <-
           %Note{contact_id: contact.id, account_id: account_id}
           |> Note.changeset(attrs)
           |> Repo.insert() do
      conn
      |> put_status(201)
      |> put_resp_header("location", "/api/notes/#{note.id}")
      |> json(%{data: note_json(note)})
    else
      false -> {:error, :forbidden}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def create(_conn, %{"contact_id" => _contact_id}) do
    {:error, :bad_request, "Missing 'note' key in request body."}
  end

  # ── Update note ──────────────────────────────────────────────────────

  def update(conn, %{"id" => id, "note" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :note),
         note when not is_nil(note) <-
           Note |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, updated} <- note |> Note.changeset(attrs) |> Repo.update() do
      json(conn, %{data: note_json(updated)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def update(_conn, %{"id" => _id}) do
    {:error, :bad_request, "Missing 'note' key in request body."}
  end

  # ── Delete note ──────────────────────────────────────────────────────

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :delete, :note),
         note when not is_nil(note) <-
           Note |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, _note} <- Repo.delete(note) do
      send_resp(conn, 204, "")
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  # ── Favorite / Unfavorite ────────────────────────────────────────────

  def favorite(conn, %{"id" => id}) do
    toggle_favorite(conn, id, true)
  end

  def unfavorite(conn, %{"id" => id}) do
    toggle_favorite(conn, id, false)
  end

  defp toggle_favorite(conn, id, value) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :note),
         note when not is_nil(note) <-
           Note |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, updated} <- note |> Note.changeset(%{favorite: value}) |> Repo.update() do
      json(conn, %{data: note_json(updated)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp fetch_contact(account_id, contact_id) do
    case Contacts.get_contact(account_id, contact_id) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  defp note_json(note) do
    %{
      id: note.id,
      contact_id: note.contact_id,
      body: note.body,
      favorite: note.favorite,
      inserted_at: note.inserted_at,
      updated_at: note.updated_at
    }
  end
end
