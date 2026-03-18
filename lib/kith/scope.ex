defmodule Kith.Scope do
  @moduledoc """
  Multi-tenancy scoping helpers.

  Every user-facing query must be scoped by `account_id` to prevent
  cross-tenant data leakage. This module provides helpers to enforce that.

  ## Usage

      import Kith.Scope

      # In context functions:
      def list_contacts(account_id) do
        Contact
        |> scope_to_account(account_id)
        |> Repo.all()
      end

      # With additional filtering:
      Contact
      |> scope_to_account(account_id)
      |> where([c], is_nil(c.deleted_at))
      |> Repo.all()
  """

  import Ecto.Query

  @doc """
  Scopes a query to the given account_id.
  """
  @spec scope_to_account(Ecto.Queryable.t(), integer()) :: Ecto.Query.t()
  def scope_to_account(queryable, account_id) when is_integer(account_id) do
    from(q in queryable, where: q.account_id == ^account_id)
  end

  @doc """
  Scopes a query to the given account_id and filters out soft-deleted records.
  For use with the contacts table which uses soft-delete via deleted_at.
  """
  @spec scope_active(Ecto.Queryable.t(), integer()) :: Ecto.Query.t()
  def scope_active(queryable, account_id) when is_integer(account_id) do
    from(q in queryable,
      where: q.account_id == ^account_id,
      where: is_nil(q.deleted_at)
    )
  end

  @doc """
  Scopes a query to soft-deleted records only (trash view).
  """
  @spec scope_trashed(Ecto.Queryable.t(), integer()) :: Ecto.Query.t()
  def scope_trashed(queryable, account_id) when is_integer(account_id) do
    from(q in queryable,
      where: q.account_id == ^account_id,
      where: not is_nil(q.deleted_at)
    )
  end

  @doc """
  Fetches a record by ID, scoped to the given account_id.
  Returns nil if not found or not in the account.
  """
  @spec get_scoped(Ecto.Queryable.t(), integer(), integer(), Ecto.Repo.t()) :: struct() | nil
  def get_scoped(queryable, id, account_id, repo) do
    queryable
    |> scope_to_account(account_id)
    |> repo.get(id)
  end

  @doc """
  Fetches a record by ID, scoped to account. Raises if not found.
  """
  @spec get_scoped!(Ecto.Queryable.t(), integer(), integer(), Ecto.Repo.t()) :: struct()
  def get_scoped!(queryable, id, account_id, repo) do
    queryable
    |> scope_to_account(account_id)
    |> repo.get!(id)
  end
end
