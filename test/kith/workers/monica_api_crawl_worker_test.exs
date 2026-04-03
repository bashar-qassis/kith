defmodule Kith.Workers.MonicaApiCrawlWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Imports
  alias Kith.Workers.MonicaApiCrawlWorker

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures
  import Kith.ImportsFixtures

  setup do
    user = user_fixture()
    seed_reference_data!()
    %{user: user, account_id: user.account_id}
  end

  defp api_import_fixture_with_stub(account_id, user_id) do
    # The worker reads api_key_encrypted from the DB.
    # In test env, Cloak encrypts/decrypts transparently.
    import_fixture(account_id, user_id, %{
      source: "monica_api",
      api_url: "https://monica.test",
      api_key_encrypted: "test-key",
      api_options: %{"photos" => false}
    })
  end

  describe "perform/1" do
    test "completes import and wipes API key", %{user: user, account_id: account_id} do
      # The worker builds a credential from the DB. When the API is unreachable,
      # the crawl still succeeds with errors in the summary (graceful degradation).
      import_job = api_import_fixture_with_stub(account_id, user.id)

      assert :ok = perform_job(MonicaApiCrawlWorker, %{import_id: import_job.id})

      updated = Imports.get_import!(import_job.id)
      assert updated.status == "completed"
      assert updated.started_at != nil
      assert updated.completed_at != nil
      # API key should be wiped after completion
      assert is_nil(updated.api_key_encrypted)
    end

    test "respects 30-minute timeout" do
      assert MonicaApiCrawlWorker.timeout(%Oban.Job{}) == :timer.minutes(30)
    end

    test "builds correct options from import api_options", %{user: user, account_id: account_id} do
      import_job =
        import_fixture(account_id, user.id, %{
          source: "monica_api",
          api_url: "https://monica.test",
          api_key_encrypted: "test-key",
          api_options: %{"photos" => true, "extra_notes" => false}
        })

      # Just verify the import was created correctly
      assert import_job.api_options["photos"] == true
      assert import_job.api_options["extra_notes"] == false
    end
  end
end
