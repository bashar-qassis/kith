defmodule KithWeb.API.DebtController do
  @moduledoc """
  REST API controller for contact debts.
  """

  use KithWeb, :controller

  alias Kith.{Debts, Contacts, Policy, Repo}
  alias Kith.Contacts.{Debt, DebtPayment}
  alias Kith.Scope, as: TenantScope
  alias KithWeb.API.Pagination

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  # ── List debts for a contact ───────────────────────────────────────

  def index(conn, %{"contact_id" => contact_id} = params) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id
    user_id = scope.user.id

    with {:ok, _contact} <- fetch_contact(account_id, contact_id) do
      query =
        Debt
        |> TenantScope.scope_to_account(account_id)
        |> where([d], d.contact_id == ^contact_id)
        |> where([d], d.is_private == false or d.creator_id == ^user_id)

      {debts, meta} = Pagination.paginate(query, params)
      debts = Repo.preload(debts, :payments)
      json(conn, Pagination.paginated_response(Enum.map(debts, &debt_json/1), meta))
    end
  end

  # ── Show debt ──────────────────────────────────────────────────────

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    account_id = scope.account.id
    user_id = scope.user.id

    case Debt |> TenantScope.scope_to_account(account_id) |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %Debt{is_private: true, creator_id: creator_id} when creator_id != user_id ->
        {:error, :not_found}

      debt ->
        debt = Repo.preload(debt, :payments)
        json(conn, %{data: debt_json(debt)})
    end
  end

  # ── Create debt ────────────────────────────────────────────────────

  def create(conn, %{"contact_id" => contact_id, "debt" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :create, :debt),
         {:ok, contact} <- fetch_contact(account_id, contact_id),
         {:ok, debt} <-
           Debts.create_debt(account_id, user.id, Map.put(attrs, "contact_id", contact.id)) do
      conn
      |> put_status(201)
      |> put_resp_header("location", "/api/debts/#{debt.id}")
      |> json(%{data: debt_json(Repo.preload(debt, :payments))})
    else
      false -> {:error, :forbidden}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def create(_conn, %{"contact_id" => _contact_id}) do
    {:error, :bad_request, "Missing 'debt' key in request body."}
  end

  # ── Update debt ────────────────────────────────────────────────────

  def update(conn, %{"id" => id, "debt" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :debt),
         debt when not is_nil(debt) <-
           Debt |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, updated} <- Debts.update_debt(debt, attrs) do
      json(conn, %{data: debt_json(Repo.preload(updated, :payments))})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def update(_conn, %{"id" => _id}) do
    {:error, :bad_request, "Missing 'debt' key in request body."}
  end

  # ── Delete debt ────────────────────────────────────────────────────

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :delete, :debt),
         debt when not is_nil(debt) <-
           Debt |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, _debt} <- Repo.delete(debt) do
      send_resp(conn, 204, "")
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  # ── Settle debt ────────────────────────────────────────────────────

  def settle(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :debt),
         debt when not is_nil(debt) <-
           Debt |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, updated} <- Debts.settle_debt(debt) do
      json(conn, %{data: debt_json(Repo.preload(updated, :payments))})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  # ── Write off debt ────────────────────────────────────────────────

  def write_off(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :debt),
         debt when not is_nil(debt) <-
           Debt |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, updated} <- Debts.write_off_debt(debt) do
      json(conn, %{data: debt_json(Repo.preload(updated, :payments))})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  # ── Add payment to debt ────────────────────────────────────────────

  def add_payment(conn, %{"id" => id, "payment" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :update, :debt),
         debt when not is_nil(debt) <-
           Debt |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, payment} <- Debts.add_payment(debt, attrs) do
      conn
      |> put_status(201)
      |> json(%{data: payment_json(payment)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  end

  def add_payment(_conn, %{"id" => _id}) do
    {:error, :bad_request, "Missing 'payment' key in request body."}
  end

  # ── Delete payment ─────────────────────────────────────────────────

  def delete_payment(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :delete, :debt),
         payment when not is_nil(payment) <-
           DebtPayment |> TenantScope.scope_to_account(account_id) |> Repo.get(id),
         {:ok, _payment} <- Repo.delete(payment) do
      send_resp(conn, 204, "")
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  # ── Private helpers ────────────────────────────────────────────────

  defp fetch_contact(account_id, contact_id) do
    case Contacts.get_contact(account_id, contact_id) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  defp debt_json(debt) do
    %{
      id: debt.id,
      contact_id: debt.contact_id,
      title: debt.title,
      amount: debt.amount,
      direction: debt.direction,
      status: debt.status,
      due_date: debt.due_date,
      notes: debt.notes,
      settled_at: debt.settled_at,
      currency_id: debt.currency_id,
      is_private: debt.is_private,
      creator_id: debt.creator_id,
      outstanding_balance: Debts.outstanding_balance(debt),
      payments: Enum.map(debt.payments, &payment_json/1),
      inserted_at: debt.inserted_at,
      updated_at: debt.updated_at
    }
  end

  defp payment_json(payment) do
    %{
      id: payment.id,
      debt_id: payment.debt_id,
      amount: payment.amount,
      paid_at: payment.paid_at,
      notes: payment.notes,
      inserted_at: payment.inserted_at,
      updated_at: payment.updated_at
    }
  end
end
