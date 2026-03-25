defmodule KithWeb.API.TagController do
  use KithWeb, :controller

  alias Kith.{Contacts, Policy}
  alias Kith.Contacts.Tag
  alias Kith.Scope, as: TenantScope

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  # GET /api/tags
  def index(conn, _params) do
    account_id = conn.assigns.current_scope.account.id
    tags = Contacts.list_tags(account_id)
    json(conn, %{data: Enum.map(tags, &tag_json/1)})
  end

  # POST /api/tags
  def create(conn, %{"tag" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :create, :tag),
         {:ok, tag} <- Contacts.create_tag(account_id, attrs) do
      conn |> put_status(201) |> json(%{data: tag_json(tag)})
    else
      false -> {:error, :forbidden}
      {:error, %Ecto.Changeset{} = cs} -> handle_tag_changeset_error(cs)
    end
  end

  # PATCH /api/tags/:id
  def update(conn, %{"id" => id, "tag" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :update, :tag) do
      true ->
        tag = Contacts.get_tag!(account_id, id)

        case Contacts.update_tag(tag, attrs) do
          {:ok, updated} -> json(conn, %{data: tag_json(updated)})
          {:error, %Ecto.Changeset{} = cs} -> handle_tag_changeset_error(cs)
        end

      false ->
        {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  # DELETE /api/tags/:id
  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :delete, :tag) do
      true ->
        tag = Contacts.get_tag!(account_id, id)
        Contacts.delete_tag(tag)
        send_resp(conn, 204, "")

      false ->
        {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  # POST /api/contacts/:contact_id/tags
  def assign(conn, %{"contact_id" => contact_id, "tag_id" => tag_id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :tag),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, contact_id),
         tag when not is_nil(tag) <- safe_get_tag(account_id, tag_id) do
      Contacts.tag_contact(contact, tag)
      json(conn, %{data: %{status: "assigned"}})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  # DELETE /api/contacts/:contact_id/tags/:tag_id
  def remove(conn, %{"contact_id" => contact_id, "tag_id" => tag_id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :tag),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, contact_id),
         tag when not is_nil(tag) <- safe_get_tag(account_id, tag_id) do
      Contacts.untag_contact(contact, tag)
      send_resp(conn, 204, "")
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  # POST /api/tags/bulk_assign
  def bulk_assign(conn, %{"tag_id" => tag_id, "contact_ids" => contact_ids})
      when is_list(contact_ids) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :tag),
         tag when not is_nil(tag) <- safe_get_tag(account_id, tag_id),
         :ok <- validate_contact_ids(account_id, contact_ids) do
      bulk_tag_contacts(account_id, contact_ids, tag)
      json(conn, %{data: %{status: "assigned", count: length(contact_ids)}})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, detail} -> {:error, :bad_request, detail}
    end
  end

  # POST /api/tags/bulk_remove
  def bulk_remove(conn, %{"tag_id" => tag_id, "contact_ids" => contact_ids})
      when is_list(contact_ids) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :tag),
         tag when not is_nil(tag) <- safe_get_tag(account_id, tag_id),
         :ok <- validate_contact_ids(account_id, contact_ids) do
      bulk_untag_contacts(account_id, contact_ids, tag)
      json(conn, %{data: %{status: "removed", count: length(contact_ids)}})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, detail} -> {:error, :bad_request, detail}
    end
  end

  defp handle_tag_changeset_error(cs) do
    if unique_constraint_error?(cs),
      do: {:error, :conflict, "A tag with this name already exists."},
      else: {:error, cs}
  end

  defp bulk_tag_contacts(account_id, contact_ids, tag) do
    Enum.each(contact_ids, fn cid ->
      contact = Contacts.get_contact(account_id, cid)
      if contact, do: Contacts.tag_contact(contact, tag)
    end)
  end

  defp bulk_untag_contacts(account_id, contact_ids, tag) do
    Enum.each(contact_ids, fn cid ->
      contact = Contacts.get_contact(account_id, cid)
      if contact, do: Contacts.untag_contact(contact, tag)
    end)
  end

  defp safe_get_tag(account_id, id) do
    Tag |> TenantScope.scope_to_account(account_id) |> Kith.Repo.get(id)
  end

  defp validate_contact_ids(account_id, contact_ids) do
    existing =
      Kith.Contacts.Contact
      |> TenantScope.scope_active(account_id)
      |> where([c], c.id in ^contact_ids)
      |> select([c], c.id)
      |> Kith.Repo.all()
      |> MapSet.new()

    missing = Enum.reject(contact_ids, &MapSet.member?(existing, &1))

    if missing == [] do
      :ok
    else
      {:error, "Contact IDs not found: #{Enum.join(missing, ", ")}"}
    end
  end

  defp unique_constraint_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_msg, opts}} ->
      Keyword.get(opts, :constraint) == :unique
    end)
  end

  defp tag_json(%Tag{} = t) do
    %{id: t.id, name: t.name, inserted_at: t.inserted_at}
  end
end
