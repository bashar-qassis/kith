defmodule Kith.Workers.ImportSourceWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Workers.ImportSourceWorker
  alias Kith.Imports

  import Kith.AccountsFixtures
  import Kith.ImportsFixtures

  setup do
    user = user_fixture()
    %{user: user, account_id: user.account_id}
  end

  describe "perform/1" do
    test "processes a vcard import", %{account_id: account_id, user: user} do
      vcf_data = "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Doe;Jane;;;\r\nFN:Jane Doe\r\nEND:VCARD\r\n"
      storage_key = "imports/test/export.vcf"
      {:ok, _} = Kith.Storage.upload_binary(vcf_data, storage_key)

      import_job =
        import_fixture(account_id, user.id, %{
          source: "vcard",
          file_name: "export.vcf",
          file_storage_key: storage_key
        })

      assert :ok = perform_job(ImportSourceWorker, %{import_id: import_job.id})

      updated = Imports.get_import!(import_job.id)
      assert updated.status == "completed"
      assert updated.summary["contacts"] >= 1
    end

    test "enqueues photo sync jobs for monica import with photos option", %{
      account_id: account_id,
      user: user
    } do
      data =
        File.read!(Path.join([__DIR__, "..", "..", "support", "fixtures", "monica_export.json"]))

      storage_key = "imports/test/monica_export.json"
      {:ok, _} = Kith.Storage.upload_binary(data, storage_key)

      import_job =
        import_fixture(account_id, user.id, %{
          source: "monica",
          file_name: "monica_export.json",
          file_storage_key: storage_key,
          api_url: "https://monica.example.com",
          api_key_encrypted: "test-api-key",
          api_options: %{"photos" => true}
        })

      # Use manual testing mode so photo sync jobs don't execute inline
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(ImportSourceWorker, %{import_id: import_job.id})
      end)

      updated = Imports.get_import!(import_job.id)
      assert updated.status == "completed"
      assert updated.summary["contacts"] == 2

      # Verify photo sync jobs were enqueued
      assert_enqueued(
        worker: Kith.Workers.PhotoBatchSyncWorker,
        args: %{import_id: import_job.id}
      )
    end

    test "marks import as failed on file not found", %{account_id: account_id, user: user} do
      import_job =
        import_fixture(account_id, user.id, %{
          source: "vcard",
          file_name: "export.vcf",
          file_storage_key: "nonexistent/path.vcf"
        })

      assert {:error, _} = perform_job(ImportSourceWorker, %{import_id: import_job.id})

      updated = Imports.get_import!(import_job.id)
      assert updated.status == "failed"
    end

    test "enqueues first_met jobs using integer Monica ID as source_contact_id", %{
      account_id: account_id,
      user: user
    } do
      data =
        File.read!(Path.join([__DIR__, "..", "..", "support", "fixtures", "monica_export.json"]))

      storage_key = "imports/test/monica_first_met_id.json"
      {:ok, _} = Kith.Storage.upload_binary(data, storage_key)

      import_job =
        import_fixture(account_id, user.id, %{
          source: "monica",
          file_name: "monica_export.json",
          file_storage_key: storage_key,
          api_url: "https://monica.example.com",
          api_key_encrypted: "test-api-key",
          api_options: %{"first_met_details" => true}
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(ImportSourceWorker, %{import_id: import_job.id})
      end)

      # Alice (id=101) has first_met_date; job must use "101" not the UUID
      assert_enqueued(
        worker: Kith.Workers.ApiSupplementWorker,
        args: %{source_contact_id: "101"}
      )

      # Bob (id=102) has no first_met_date — no job for him
      refute_enqueued(
        worker: Kith.Workers.ApiSupplementWorker,
        args: %{source_contact_id: "102"}
      )
    end
  end
end
