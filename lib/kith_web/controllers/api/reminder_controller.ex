defmodule KithWeb.API.ReminderController do
  use KithWeb, :controller

  alias Kith.{Contacts, Policy, Reminders}
  alias Kith.Reminders.{Reminder, ReminderInstance}
  alias Kith.Scope, as: TenantScope
  alias KithWeb.API.Pagination

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  # GET /api/contacts/:contact_id/reminders
  def index(conn, %{"contact_id" => contact_id} = params) do
    account_id = conn.assigns.current_scope.account.id

    case Contacts.get_contact(account_id, contact_id) do
      nil ->
        {:error, :not_found}

      _contact ->
        query =
          Reminder
          |> TenantScope.scope_to_account(account_id)
          |> where([r], r.contact_id == ^contact_id)

        {reminders, meta} = Pagination.paginate(query, params)
        json(conn, Pagination.paginated_response(Enum.map(reminders, &reminder_json/1), meta))
    end
  end

  # GET /api/reminders/upcoming
  def upcoming(conn, params) do
    account_id = conn.assigns.current_scope.account.id

    window =
      case params["window"] do
        "30" -> 30
        "60" -> 60
        "90" -> 90
        nil -> 30
        _ -> :invalid
      end

    if window == :invalid do
      {:error, :bad_request, "Invalid window. Valid values: 30, 60, 90."}
    else
      cutoff = Date.add(Date.utc_today(), window)

      query =
        Reminder
        |> TenantScope.scope_to_account(account_id)
        |> where([r], not is_nil(r.next_reminder_date))
        |> where([r], r.next_reminder_date <= ^cutoff)
        |> order_by([r], asc: r.next_reminder_date)

      {reminders, meta} = Pagination.paginate(query, params)
      json(conn, Pagination.paginated_response(Enum.map(reminders, &reminder_json/1), meta))
    end
  end

  # GET /api/reminders/:id
  def show(conn, %{"id" => id}) do
    account_id = conn.assigns.current_scope.account.id

    case Reminder |> TenantScope.scope_to_account(account_id) |> Kith.Repo.get(id) do
      nil -> {:error, :not_found}
      reminder -> json(conn, %{data: reminder_json(reminder)})
    end
  end

  # POST /api/contacts/:contact_id/reminders
  def create(conn, %{"contact_id" => contact_id, "reminder" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :create, :reminder),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, contact_id) do
      reminder_attrs = Map.put(attrs, "contact_id", contact.id)

      case Reminders.create_reminder(account_id, user.id, reminder_attrs) do
        {:ok, reminder} ->
          conn |> put_status(201) |> json(%{data: reminder_json(reminder)})

        {:error, _step, %Ecto.Changeset{} = cs, _changes} ->
          {:error, cs}

        {:error, %Ecto.Changeset{} = cs} ->
          {:error, cs}

        {:error, reason} ->
          {:error, :bad_request, inspect(reason)}
      end
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  def create(_conn, %{"contact_id" => _}) do
    {:error, :bad_request, "Missing 'reminder' key in request body."}
  end

  # PATCH /api/reminders/:id
  def update(conn, %{"id" => id, "reminder" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :reminder) do
      case Reminder |> TenantScope.scope_to_account(account_id) |> Kith.Repo.get(id) do
        nil ->
          {:error, :not_found}

        reminder ->
          case Reminders.update_reminder(reminder, attrs) do
            {:ok, updated} ->
              json(conn, %{data: reminder_json(updated)})

            {:error, _step, %Ecto.Changeset{} = cs, _changes} ->
              {:error, cs}

            {:error, %Ecto.Changeset{} = cs} ->
              {:error, cs}
          end
      end
    else
      false -> {:error, :forbidden}
    end
  end

  # DELETE /api/reminders/:id
  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :delete, :reminder) do
      case Reminder |> TenantScope.scope_to_account(account_id) |> Kith.Repo.get(id) do
        nil ->
          {:error, :not_found}

        reminder ->
          case Reminders.delete_reminder(reminder) do
            {:ok, _} -> send_resp(conn, 204, "")
            {:error, reason} -> {:error, :bad_request, inspect(reason)}
          end
      end
    else
      false -> {:error, :forbidden}
    end
  end

  # POST /api/reminder_instances/:id/resolve
  def resolve_instance(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :reminder) do
      case get_instance(account_id, id) do
        nil ->
          {:error, :not_found}

        instance ->
          case Reminders.resolve_instance(instance) do
            {:ok, _} -> json(conn, %{data: %{status: "resolved"}})
            {:error, reason} -> {:error, :bad_request, inspect(reason)}
          end
      end
    else
      false -> {:error, :forbidden}
    end
  end

  # POST /api/reminder_instances/:id/dismiss
  def dismiss_instance(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :reminder) do
      case get_instance(account_id, id) do
        nil ->
          {:error, :not_found}

        instance ->
          case Reminders.dismiss_instance(instance) do
            {:ok, _} -> json(conn, %{data: %{status: "dismissed"}})
            {:error, reason} -> {:error, :bad_request, inspect(reason)}
          end
      end
    else
      false -> {:error, :forbidden}
    end
  end

  defp get_instance(account_id, id) do
    ReminderInstance
    |> join(:inner, [ri], r in Reminder, on: ri.reminder_id == r.id)
    |> where([_ri, r], r.account_id == ^account_id)
    |> where([ri], ri.id == ^id)
    |> Kith.Repo.one()
  end

  defp reminder_json(%Reminder{} = r) do
    %{
      id: r.id,
      contact_id: r.contact_id,
      type: r.type,
      title: r.title,
      next_reminder_date: r.next_reminder_date,
      frequency: r.frequency,
      inserted_at: r.inserted_at,
      updated_at: r.updated_at
    }
  end
end
