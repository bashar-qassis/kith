defmodule KithWeb.API.ContactController do
  @moduledoc """
  REST API controller for contacts.

  Provides CRUD operations plus archive/unarchive, favorite/unfavorite,
  merge, and trash/restore endpoints.
  """

  use KithWeb, :controller

  alias Kith.{Contacts, Policy}
  alias Kith.Contacts.Contact
  alias Kith.Scope, as: TenantScope
  alias KithWeb.API.{ContactJSON, ErrorJSON, Includes, Pagination}

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  # ── List contacts ─────────────────────────────────────────────────────

  def index(conn, params) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id
    user = scope.user

    # Trashed filter — admin only
    if params["trashed"] == "true" do
      unless Policy.can?(user, :manage, :contact) do
        return_forbidden(conn)
      else
        query = TenantScope.scope_trashed(Contact, account_id)
        {contacts, meta} = Pagination.paginate(query, params)
        json(conn, Pagination.paginated_response(Enum.map(contacts, &ContactJSON.data/1), meta))
      end
    else
      with {:ok, includes} <- Includes.parse_includes(params, :contact_list) do
        preloads = Includes.to_preloads(includes)

        query =
          Contact
          |> TenantScope.scope_active(account_id)
          |> apply_filters(params)
          |> maybe_search(params, account_id)

        query = if preloads != [], do: from(q in query, preload: ^preloads), else: query

        {contacts, meta} = Pagination.paginate(query, params)

        data =
          Enum.map(contacts, fn c ->
            if includes == [],
              do: ContactJSON.data(c),
              else: ContactJSON.data_with_includes(c, includes)
          end)

        json(conn, Pagination.paginated_response(data, meta))
      else
        {:error, detail} -> {:error, :bad_request, detail}
      end
    end
  end

  # ── Show contact ──────────────────────────────────────────────────────

  def show(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id

    with {:ok, includes} <- Includes.parse_includes(params, :contact_show) do
      preloads = Includes.to_preloads(includes)

      case Contacts.get_contact(account_id, id, preload: preloads) do
        nil ->
          {:error, :not_found}

        contact ->
          data =
            if includes == [],
              do: ContactJSON.data(contact),
              else: ContactJSON.data_with_includes(contact, includes)

          json(conn, %{data: data})
      end
    else
      {:error, detail} -> {:error, :bad_request, detail}
    end
  end

  # ── Create contact ────────────────────────────────────────────────────

  def create(conn, %{"contact" => contact_params}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :create, :contact),
         {:ok, contact} <- Contacts.create_contact(account_id, contact_params) do
      conn
      |> put_status(201)
      |> put_resp_header("location", "/api/contacts/#{contact.id}")
      |> json(%{data: ContactJSON.data(contact)})
    else
      false -> {:error, :forbidden}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def create(_conn, _params) do
    {:error, :bad_request, "Missing 'contact' key in request body."}
  end

  # ── Update contact ────────────────────────────────────────────────────

  def update(conn, %{"id" => id, "contact" => contact_params}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :contact),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, id),
         safe_params = Map.drop(contact_params, ["account_id", "deleted_at", "id"]),
         {:ok, updated} <- Contacts.update_contact(contact, safe_params) do
      json(conn, %{data: ContactJSON.data(updated)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def update(_conn, %{"id" => _id}) do
    {:error, :bad_request, "Missing 'contact' key in request body."}
  end

  # ── Delete (soft-delete) contact ──────────────────────────────────────

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :delete, :contact),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, id),
         {:ok, _contact} <- Contacts.soft_delete_contact(contact) do
      send_resp(conn, 204, "")
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  # ── Archive / Unarchive ───────────────────────────────────────────────

  def archive(conn, %{"contact_id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :contact),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, id),
         {:ok, updated} <- Contacts.archive_contact(contact) do
      json(conn, %{data: ContactJSON.data(updated)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def unarchive(conn, %{"contact_id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :contact),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, id),
         {:ok, updated} <- Contacts.unarchive_contact(contact) do
      json(conn, %{data: ContactJSON.data(updated)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  # ── Favorite / Unfavorite ─────────────────────────────────────────────

  def favorite(conn, %{"contact_id" => id}) do
    toggle_favorite(conn, id, true)
  end

  def unfavorite(conn, %{"contact_id" => id}) do
    toggle_favorite(conn, id, false)
  end

  defp toggle_favorite(conn, id, value) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :contact),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, id),
         {:ok, updated} <- Contacts.update_contact(contact, %{"favorite" => value}) do
      json(conn, %{data: ContactJSON.data(updated)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  # ── Merge ─────────────────────────────────────────────────────────────

  def merge(conn, %{"survivor_id" => survivor_id, "non_survivor_id" => non_survivor_id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :contact) do
      # Validate both contacts belong to this account
      survivor = Contacts.get_contact(account_id, survivor_id)
      non_survivor = Contacts.get_contact(account_id, non_survivor_id)

      cond do
        is_nil(survivor) or is_nil(non_survivor) ->
          {:error, :not_found}

        survivor_id == non_survivor_id ->
          {:error, :bad_request, "Cannot merge a contact with itself."}

        true ->
          case Contacts.merge_contacts(survivor.id, non_survivor.id) do
            {:ok, merged} ->
              json(conn, %{data: ContactJSON.data(merged)})

            {:error, reason} when is_binary(reason) ->
              {:error, :bad_request, reason}

            {:error, _step, %Ecto.Changeset{} = cs, _changes} ->
              {:error, cs}

            {:error, reason} ->
              {:error, :bad_request, inspect(reason)}
          end
      end
    else
      false -> {:error, :forbidden}
    end
  end

  def merge(_conn, _params) do
    {:error, :bad_request, "Missing survivor_id and non_survivor_id."}
  end

  # ── Restore (from trash) ──────────────────────────────────────────────

  def restore(conn, %{"contact_id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :manage, :contact) do
      # Look in trashed contacts specifically
      contact =
        Contact
        |> TenantScope.scope_trashed(account_id)
        |> Kith.Repo.get(id)

      cond do
        is_nil(contact) ->
          # Check if it exists at all (active) — if so, 422
          case Contacts.get_contact(account_id, id) do
            nil -> {:error, :not_found}
            _active -> {:error, :bad_request, "Contact is not in trash."}
          end

        true ->
          case Contacts.restore_contact(contact) do
            {:ok, restored} -> json(conn, %{data: ContactJSON.data(restored)})
            {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
          end
      end
    else
      false -> {:error, :forbidden}
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp apply_filters(query, params) do
    query
    |> filter_archived(params)
    |> filter_favorite(params)
    |> filter_tags(params)
  end

  defp filter_archived(query, %{"archived" => "true"}) do
    from(q in query, where: q.is_archived == true)
  end

  defp filter_archived(query, _params) do
    from(q in query, where: q.is_archived == false)
  end

  defp filter_favorite(query, %{"favorite" => "true"}) do
    from(q in query, where: q.favorite == true)
  end

  defp filter_favorite(query, _params), do: query

  defp filter_tags(query, %{"tag_ids" => tag_ids}) when is_list(tag_ids) and tag_ids != [] do
    ids = Enum.map(tag_ids, &to_integer/1) |> Enum.reject(&is_nil/1)

    if ids == [] do
      query
    else
      from(q in query,
        join: ct in "contact_tags",
        on: ct.contact_id == q.id,
        where: ct.tag_id in ^ids,
        distinct: true
      )
    end
  end

  defp filter_tags(query, _params), do: query

  defp maybe_search(query, %{"q" => q}, _account_id) when is_binary(q) and q != "" do
    search = "%#{String.replace(q, ~r/[%_\\]/, "\\\\\\0")}%"

    from(q_query in query,
      left_join: cf in Kith.Contacts.ContactField,
      on: cf.contact_id == q_query.id,
      where:
        ilike(q_query.first_name, ^search) or
          ilike(q_query.last_name, ^search) or
          ilike(q_query.display_name, ^search) or
          ilike(q_query.nickname, ^search) or
          ilike(q_query.company, ^search) or
          ilike(cf.value, ^search),
      distinct: true
    )
  end

  defp maybe_search(query, _params, _account_id), do: query

  defp return_forbidden(conn) do
    conn
    |> put_status(403)
    |> put_resp_content_type("application/problem+json")
    |> json(ErrorJSON.render(403, "Admin role required.", conn.request_path))
  end

  defp to_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_integer(val) when is_integer(val), do: val
  defp to_integer(_), do: nil
end
