defmodule Kith.Workers.ImmichSyncWorkerTest do
  use Kith.DataCase, async: true

  alias Kith.Workers.ImmichSyncWorker
  alias Kith.Accounts.Account
  alias Kith.Repo

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup do
    user = user_fixture()
    account = Repo.get!(Account, user.account_id)
    %{account: account, user: user}
  end

  describe "perform/1" do
    test "skips account when immich_status is error", %{account: account} do
      {:ok, account} =
        account
        |> Account.immich_sync_changeset(%{immich_status: "error"})
        |> Repo.update()

      job = %Oban.Job{args: %{"account_id" => account.id}}
      assert :ok = ImmichSyncWorker.perform(job)
    end

    test "skips account when immich_enabled is false", %{account: account} do
      job = %Oban.Job{args: %{"account_id" => account.id}}
      assert :ok = ImmichSyncWorker.perform(job)
    end

    test "skips account when credentials are missing", %{account: account} do
      {:ok, account} =
        account
        |> Account.immich_changeset(%{immich_enabled: true})
        |> Repo.update()

      job = %Oban.Job{args: %{"account_id" => account.id}}
      assert :ok = ImmichSyncWorker.perform(job)
    end
  end

  describe "circuit breaker" do
    test "increments failure counter on sync failure", %{account: account} do
      {:ok, account} =
        account
        |> Account.immich_changeset(%{
          immich_enabled: true,
          immich_base_url: "http://127.0.0.1:1",
          immich_api_key: "fake-key"
        })
        |> Repo.update()

      job = %Oban.Job{args: %{"account_id" => account.id}}
      # Will fail because host is unreachable
      ImmichSyncWorker.perform(job)

      reloaded = Repo.get!(Account, account.id)
      assert reloaded.immich_consecutive_failures >= 1
    end
  end
end
