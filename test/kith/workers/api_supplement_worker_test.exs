defmodule Kith.Workers.ApiSupplementWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Contacts
  alias Kith.Imports
  alias Kith.Repo
  alias Kith.Workers.ApiSupplementWorker

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures
  import Kith.ImportsFixtures

  @stub_name :api_supplement_worker_stub

  setup do
    user = user_fixture()
    seed_reference_data!()
    %{user: user, account_id: user.account_id}
  end

  describe "perform/1" do
    test "discards when import not found" do
      assert {:discard, _} =
               perform_job(ApiSupplementWorker, %{
                 import_id: 999_999,
                 contact_id: 1,
                 source_contact_id: "101",
                 key: "first_met_details"
               })
    end

    test "discards when contact not found", %{account_id: account_id, user: user} do
      import_job =
        import_fixture(account_id, user.id, %{
          source: "monica",
          api_url: "https://monica.example.com",
          api_key_encrypted: "test-key"
        })

      assert {:discard, _} =
               perform_job(ApiSupplementWorker, %{
                 import_id: import_job.id,
                 contact_id: 999_999,
                 source_contact_id: "101",
                 key: "first_met_details"
               })
    end

    test "snoozes 60 seconds on rate limit (429)", %{account_id: account_id, user: user} do
      contact = contact_fixture(account_id)

      import_job =
        import_fixture(account_id, user.id, %{
          source: "monica",
          api_url: "https://monica.example.com",
          api_key_encrypted: "test-key"
        })

      Req.Test.stub(@stub_name, fn conn -> Plug.Conn.send_resp(conn, 429, "") end)
      Process.put({ApiSupplementWorker, :req_options}, plug: {Req.Test, @stub_name}, retry: false)

      assert {:snooze, 60} =
               perform_job(ApiSupplementWorker, %{
                 import_id: import_job.id,
                 contact_id: contact.id,
                 source_contact_id: "101",
                 key: "first_met_details"
               })
    end

    test "sets first_met_through_id when first_met_through_uuid resolves to a local contact", %{
      account_id: account_id,
      user: user
    } do
      alice = contact_fixture(account_id, %{first_name: "Alice"})
      bob = contact_fixture(account_id, %{first_name: "Bob"})

      import_job =
        import_fixture(account_id, user.id, %{
          source: "monica",
          api_url: "https://monica.example.com",
          api_key_encrypted: "test-key"
        })

      {:ok, _} =
        Imports.record_imported_entity(import_job, "contact", "alice-uuid", "contact", alice.id)

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "first_met_where" => "At the park",
            "first_met_additional_information" => "Summer 2020",
            "first_met_through" => %{"data" => %{"uuid" => "alice-uuid"}}
          }
        })
      end)

      Process.put({ApiSupplementWorker, :req_options}, plug: {Req.Test, @stub_name})

      assert :ok =
               perform_job(ApiSupplementWorker, %{
                 import_id: import_job.id,
                 contact_id: bob.id,
                 source_contact_id: "102",
                 key: "first_met_details"
               })

      updated = Repo.get!(Contacts.Contact, bob.id)
      assert updated.first_met_where == "At the park"
      assert updated.first_met_additional_info == "Summer 2020"
      assert updated.first_met_through_id == alice.id
    end

    test "updates first_met fields without setting first_met_through_id when uuid is nil", %{
      account_id: account_id,
      user: user
    } do
      contact = contact_fixture(account_id)

      import_job =
        import_fixture(account_id, user.id, %{
          source: "monica",
          api_url: "https://monica.example.com",
          api_key_encrypted: "test-key"
        })

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "first_met_where" => "At a conference",
            "first_met_additional_information" => nil,
            "first_met_through" => nil
          }
        })
      end)

      Process.put({ApiSupplementWorker, :req_options}, plug: {Req.Test, @stub_name})

      assert :ok =
               perform_job(ApiSupplementWorker, %{
                 import_id: import_job.id,
                 contact_id: contact.id,
                 source_contact_id: "103",
                 key: "first_met_details"
               })

      updated = Repo.get!(Contacts.Contact, contact.id)
      assert updated.first_met_where == "At a conference"
      assert is_nil(updated.first_met_through_id)
    end

    test "updates first_met fields gracefully when first_met_through_uuid has no import record",
         %{account_id: account_id, user: user} do
      contact = contact_fixture(account_id)

      import_job =
        import_fixture(account_id, user.id, %{
          source: "monica",
          api_url: "https://monica.example.com",
          api_key_encrypted: "test-key"
        })

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "first_met_where" => "Online",
            "first_met_additional_information" => nil,
            "first_met_through" => %{"data" => %{"uuid" => "nonexistent-uuid"}}
          }
        })
      end)

      Process.put({ApiSupplementWorker, :req_options}, plug: {Req.Test, @stub_name})

      assert :ok =
               perform_job(ApiSupplementWorker, %{
                 import_id: import_job.id,
                 contact_id: contact.id,
                 source_contact_id: "104",
                 key: "first_met_details"
               })

      updated = Repo.get!(Contacts.Contact, contact.id)
      assert updated.first_met_where == "Online"
      assert is_nil(updated.first_met_through_id)
    end
  end
end
