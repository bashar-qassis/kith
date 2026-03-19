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
  Returns `:ok` or `{:error, reason}`.
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
          {:ok, _people} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
