defmodule Kith.Immich.SettingsTest do
  use Kith.DataCase, async: true

  alias Kith.Immich.Settings
  alias Kith.Accounts.Account
  alias Kith.Repo

  import Kith.AccountsFixtures

  setup do
    user = user_fixture()
    account = Repo.get!(Account, user.account_id)
    %{account: account}
  end

  describe "get_settings/1" do
    test "returns default settings for new account", %{account: account} do
      settings = Settings.get_settings(account)

      assert settings.base_url == nil
      assert settings.api_key == nil
      assert settings.enabled == false
      assert settings.status == "disabled"
      assert settings.consecutive_failures == 0
      assert settings.last_synced_at == nil
    end
  end

  describe "update_settings/2" do
    test "persists Immich URL and enabled flag", %{account: account} do
      {:ok, updated} =
        Settings.update_settings(account, %{
          immich_base_url: "https://immich.example.com",
          immich_enabled: true
        })

      assert updated.immich_base_url == "https://immich.example.com"
      assert updated.immich_enabled == true
    end

    test "validates URL format", %{account: account} do
      {:error, changeset} =
        Settings.update_settings(account, %{
          immich_base_url: "not-a-url"
        })

      assert errors_on(changeset).immich_base_url
    end

    test "encrypts API key via Vault", %{account: account} do
      {:ok, updated} =
        Settings.update_settings(account, %{
          immich_api_key: "my-secret-key-12345"
        })

      # The API key is decrypted transparently by Cloak
      assert updated.immich_api_key == "my-secret-key-12345"

      # But in the raw DB it should be encrypted (not plaintext)
      raw =
        Repo.one(
          from a in "accounts",
            where: a.id == ^updated.id,
            select: a.immich_api_key
        )

      refute raw == "my-secret-key-12345"
    end
  end

  describe "test_connection/1" do
    test "returns error when URL is missing", %{account: account} do
      assert {:error, :missing_url} = Settings.test_connection(account)
    end

    test "returns error when API key is missing", %{account: account} do
      {:ok, updated} =
        Settings.update_settings(account, %{immich_base_url: "https://immich.example.com"})

      assert {:error, :missing_api_key} = Settings.test_connection(updated)
    end
  end
end
