defmodule Kith.Immich.Settings do
  @moduledoc """
  Context for managing per-account Immich integration settings.

  Handles credential storage (encrypted API key), connection testing,
  and integration enable/disable.
  """

  alias Kith.Accounts.Account
  alias Kith.Repo

  @doc "Returns the current Immich settings for an account."
  def get_settings(%Account{} = account) do
    %{
      base_url: account.immich_base_url,
      api_key: account.immich_api_key,
      enabled: account.immich_enabled,
      status: account.immich_status,
      consecutive_failures: account.immich_consecutive_failures,
      last_synced_at: account.immich_last_synced_at
    }
  end

  @doc """
  Updates Immich settings for an account.
  The API key is encrypted at rest via Kith.Vault.
  """
  def update_settings(%Account{} = account, attrs) do
    account
    |> Account.immich_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Tests the connection to the configured Immich instance.
  Decrypts the API key and performs a live API call.
  Returns `{:ok, person_count}` or `{:error, reason}`.
  """
  def test_connection(%Account{} = account) do
    base_url = account.immich_base_url
    api_key = account.immich_api_key

    cond do
      is_nil(base_url) || base_url == "" ->
        {:error, :missing_url}

      is_nil(api_key) || api_key == "" ->
        {:error, :missing_api_key}

      true ->
        case Kith.Immich.Client.list_people(base_url, api_key) do
          {:ok, people} -> {:ok, length(people)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc "Enables the Immich integration for an account."
  def enable(%Account{} = account) do
    account
    |> Ecto.Changeset.change(%{immich_enabled: true, immich_status: "ok"})
    |> Kith.Repo.update()
  end

  @doc "Disables the Immich integration for an account."
  def disable(%Account{} = account) do
    account
    |> Ecto.Changeset.change(%{immich_enabled: false, immich_status: "disabled"})
    |> Kith.Repo.update()
  end

  @doc "Triggers an immediate Immich sync by enqueuing the worker."
  def trigger_manual_sync(%Account{} = account) do
    %{account_id: account.id}
    |> Kith.Workers.ImmichSyncWorker.new()
    |> Oban.insert()
  end

  @doc "Returns sync status information for the account."
  def get_sync_status(%Account{} = account) do
    import Ecto.Query

    needs_review_count =
      from(c in Kith.Contacts.Contact,
        where: c.account_id == ^account.id,
        where: c.immich_status == "needs_review",
        where: is_nil(c.deleted_at)
      )
      |> Kith.Repo.aggregate(:count)

    %{
      enabled: account.immich_enabled,
      status: account.immich_status,
      last_synced_at: account.immich_last_synced_at,
      consecutive_failures: account.immich_consecutive_failures,
      needs_review_count: needs_review_count
    }
  end
end
