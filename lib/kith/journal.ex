defmodule Kith.Journal do
  @moduledoc """
  Context module for journal entries.

  Journal entries are account-level (not contact-scoped). They support privacy
  filtering: private entries are visible only to their author.
  """

  import Ecto.Query, warn: false
  import Kith.Scope

  alias Kith.Journal.Entry
  alias Kith.Repo

  @doc """
  Lists journal entries for the given account.

  ## Options

    * `:author_id` - when set, private entries are filtered to only those
      authored by this user. Public entries are always included.
    * `:mood` - filter entries by mood value.
  """
  def list_entries(account_id, opts \\ []) do
    author_id = Keyword.get(opts, :author_id)
    mood = Keyword.get(opts, :mood)

    Entry
    |> scope_to_account(account_id)
    |> maybe_filter_private(author_id)
    |> maybe_filter_mood(mood)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  @doc "Fetches a single entry by ID, scoped to the account. Raises if not found."
  def get_entry!(account_id, id) do
    Entry |> scope_to_account(account_id) |> Repo.get!(id)
  end

  @doc "Fetches a single entry by ID, scoped to the account. Returns nil if not found."
  def get_entry(account_id, id) do
    Entry |> scope_to_account(account_id) |> Repo.get(id)
  end

  @doc "Creates a journal entry for the given account and author."
  def create_entry(account_id, author_id, attrs) do
    %Entry{account_id: account_id, author_id: author_id}
    |> Entry.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a journal entry."
  def update_entry(%Entry{} = entry, attrs) do
    entry |> Entry.changeset(attrs) |> Repo.update()
  end

  @doc "Deletes a journal entry."
  def delete_entry(%Entry{} = entry), do: Repo.delete(entry)

  @doc "Lists entries filtered by mood for the given account."
  def entries_by_mood(account_id, mood) do
    Entry
    |> scope_to_account(account_id)
    |> where([e], e.mood == ^mood)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_private(query, nil), do: query

  defp maybe_filter_private(query, author_id) do
    where(query, [e], e.is_private == false or e.author_id == ^author_id)
  end

  defp maybe_filter_mood(query, nil), do: query
  defp maybe_filter_mood(query, mood), do: where(query, [e], e.mood == ^mood)
end
