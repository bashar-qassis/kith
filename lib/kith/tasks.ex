defmodule Kith.Tasks do
  @moduledoc """
  The Tasks context — task management for contacts.
  """

  import Ecto.Query, warn: false
  import Kith.Scope

  alias Kith.Repo
  alias Kith.Tasks.Task

  def list_tasks(account_id, opts \\ []) do
    contact_id = Keyword.get(opts, :contact_id)
    status = Keyword.get(opts, :status)

    Task
    |> scope_to_account(account_id)
    |> maybe_filter_contact(contact_id)
    |> maybe_filter_status(status)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  def get_task!(account_id, id) do
    Task |> scope_to_account(account_id) |> Repo.get!(id)
  end

  def create_task(account_id, creator_id, attrs) do
    %Task{account_id: account_id, creator_id: creator_id}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task |> Task.changeset(attrs) |> Repo.update()
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)

  def complete_task(%Task{} = task) do
    update_task(task, %{status: "completed"})
  end

  def overdue_tasks(account_id) do
    today = Date.utc_today()

    Task
    |> scope_to_account(account_id)
    |> where([t], t.status in ["pending", "in_progress"])
    |> where([t], not is_nil(t.due_date) and t.due_date < ^today)
    |> order_by([t], asc: t.due_date)
    |> Repo.all()
  end

  defp maybe_filter_contact(query, nil), do: query
  defp maybe_filter_contact(query, contact_id), do: where(query, [t], t.contact_id == ^contact_id)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)
end
