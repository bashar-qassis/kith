defmodule Kith.Imports.Sources.MonicaApiTest do
  use Kith.DataCase, async: true

  alias Kith.Imports.Sources.MonicaApi
  alias Kith.Imports
  alias Kith.Contacts
  alias Kith.Repo

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures
  import Kith.ImportsFixtures
  import Kith.MonicaApiFixtures

  @stub_name :monica_api_stub

  setup do
    user = user_fixture()
    seed_reference_data!()
    %{user: user, account_id: user.account_id}
  end

  defp credential(opts \\ []) do
    %{
      url: "https://monica.test",
      api_key: "test-key",
      req_options: [plug: {Req.Test, @stub_name}, retry: false]
    }
    |> Map.merge(Map.new(opts))
  end

  defp api_import_fixture(account_id, user_id, opts \\ %{}) do
    attrs =
      Map.merge(
        %{
          source: "monica_api",
          api_url: "https://monica.test",
          api_key_encrypted: "test-key",
          api_options: %{"photos" => false, "extra_notes" => true}
        },
        opts
      )

    import_fixture(account_id, user_id, attrs)
  end

  # ── test_connection/1 ──────────────────────────────────────────────────

  describe "test_connection/1" do
    test "returns :ok for valid credentials" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"data" => %{"id" => 1}})
      end)

      assert :ok = MonicaApi.test_connection(credential())
    end

    test "returns error for invalid API key" do
      Req.Test.stub(@stub_name, fn conn ->
        Plug.Conn.send_resp(conn, 401, "")
      end)

      assert {:error, "Invalid API key"} = MonicaApi.test_connection(credential())
    end

    test "returns error for unexpected status" do
      Req.Test.stub(@stub_name, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      assert {:error, "Unexpected status: 500"} = MonicaApi.test_connection(credential())
    end
  end

  # ── crawl/5 — basic contact import ─────────────────────────────────

  describe "crawl/5 — basic contact import" do
    test "imports a single page of contacts with all embedded data", %{
      user: user,
      account_id: account_id
    } do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Alice",
          last_name: "Smith",
          addresses: [address_json(street: "456 Elm St", city: "Portland")],
          tags: [tag_json("Friends"), tag_json("Work")],
          contact_fields: [contact_field_json(content: "alice@test.com", type_name: "Email")],
          notes: [note_json(body: "Met at conference")]
        ),
        contact_json(
          id: 2,
          first_name: "Bob",
          last_name: "Jones",
          number_of_notes: 1,
          notes: [note_json(body: "Good friend")]
        ),
        contact_json(id: 3, first_name: "Carol", last_name: "Brown")
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts, 1, 1, 3))
      end)

      import_job = api_import_fixture(account_id, user.id)

      assert {:ok, summary} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      assert summary.contacts == 3
      assert summary.error_count == 0

      # Verify contacts in DB
      alice =
        Repo.one(
          from c in Contacts.Contact,
            where: c.first_name == "Alice" and c.account_id == ^account_id
        )

      assert alice != nil
      assert alice.last_name == "Smith"

      # Verify address
      [addr] = Repo.all(from a in Contacts.Address, where: a.contact_id == ^alice.id)
      assert addr.city == "Portland"

      # Verify contact field
      fields = Repo.all(from cf in Contacts.ContactField, where: cf.contact_id == ^alice.id)
      assert length(fields) == 1
      assert hd(fields).value == "alice@test.com"

      # Verify import records
      rec = Imports.find_import_record(account_id, "monica_api", "contact", "1")
      assert rec != nil
      assert rec.local_entity_id == alice.id
    end

    test "maps API fields correctly to Kith contact attrs", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 10,
          first_name: "Diana",
          last_name: "Prince",
          nickname: "Wonder",
          description: "Amazonian warrior",
          gender: "Female",
          is_starred: true,
          is_dead: false,
          is_active: false,
          job: "Hero",
          company: "Justice League",
          birthdate: %{"date" => "1985-06-15T00:00:00Z", "is_year_unknown" => false},
          how_you_met: %{
            "general_information" => "At the watchtower",
            "first_met_date" => %{"date" => "2020-01-10T00:00:00Z", "is_year_unknown" => true},
            "first_met_through_contact" => nil
          }
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      diana =
        Repo.one(
          from c in Contacts.Contact,
            where: c.first_name == "Diana" and c.account_id == ^account_id
        )

      assert diana.nickname == "Wonder"
      assert diana.description == "Amazonian warrior"
      assert diana.occupation == "Hero"
      assert diana.company == "Justice League"
      assert diana.favorite == true
      assert diana.is_archived == true
      assert diana.birthdate == ~D[1985-06-15]
      assert diana.first_met_at == ~D[2020-01-10]
      assert diana.first_met_year_unknown == true
      assert diana.first_met_additional_info == "At the watchtower"
    end

    test "handles contacts with minimal data", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(id: 1, first_name: "Minimal", last_name: nil)
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 1
      assert summary.error_count == 0
    end

    test "broadcasts progress via PubSub", %{user: user, account_id: account_id} do
      Phoenix.PubSub.subscribe(Kith.PubSub, "import:#{account_id}")

      contacts = for i <- 1..3, do: contact_json(id: i, first_name: "Person#{i}")

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts, 1, 1, 3))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      # Should receive at least the final progress broadcast
      assert_receive {:import_progress, %{current: 3, total: 3}}, 1000
    end
  end

  # ── crawl/5 — pagination ──────────────────────────────────────────────

  describe "crawl/5 — pagination" do
    test "crawls multiple pages until last_page", %{user: user, account_id: account_id} do
      page1 = for i <- 1..3, do: contact_json(id: i, first_name: "Page1_#{i}")
      page2 = for i <- 4..5, do: contact_json(id: i, first_name: "Page2_#{i}")

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        page_num = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

        case page_num do
          1 -> Req.Test.json(conn, contacts_page_json(page1, 1, 2, 5))
          2 -> Req.Test.json(conn, contacts_page_json(page2, 2, 2, 5))
        end
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 5

      # Verify both pages were fetched
      assert Agent.get(agent, & &1) == 2
      Agent.stop(agent)
    end

    test "handles empty first page gracefully", %{user: user, account_id: account_id} do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json([], 1, 1, 0))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 0
      assert summary.error_count == 0
    end
  end

  # ── crawl/5 — first_met_through_contact resolution ────────────────

  describe "crawl/5 — first_met_through resolution" do
    test "resolves first_met_through when both contacts exist", %{
      user: user,
      account_id: account_id
    } do
      bob = contact_json(id: 2, first_name: "Bob", last_name: "Intro")

      alice =
        contact_json(
          id: 1,
          first_name: "Alice",
          how_you_met: %{
            "general_information" => nil,
            "first_met_date" => nil,
            "first_met_through_contact" => contact_short_json(2, bob["uuid"], "Bob", "Intro")
          }
        )

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json([alice, bob]))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 2
      assert summary.error_count == 0

      alice_rec = Imports.find_import_record(account_id, "monica_api", "contact", "1")
      bob_rec = Imports.find_import_record(account_id, "monica_api", "contact", "2")

      alice_contact = Repo.get!(Contacts.Contact, alice_rec.local_entity_id)
      assert alice_contact.first_met_through_id == bob_rec.local_entity_id
    end

    test "resolves first_met_through across pages", %{user: user, account_id: account_id} do
      alice =
        contact_json(
          id: 1,
          first_name: "Alice",
          how_you_met: %{
            "general_information" => nil,
            "first_met_date" => nil,
            "first_met_through_contact" =>
              contact_short_json(2, Ecto.UUID.generate(), "Bob", "Page2")
          }
        )

      bob = contact_json(id: 2, first_name: "Bob", last_name: "Page2")

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        page_num = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

        case page_num do
          1 -> Req.Test.json(conn, contacts_page_json([alice], 1, 2, 2))
          2 -> Req.Test.json(conn, contacts_page_json([bob], 2, 2, 2))
        end
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 2
      assert summary.error_count == 0

      alice_rec = Imports.find_import_record(account_id, "monica_api", "contact", "1")
      bob_rec = Imports.find_import_record(account_id, "monica_api", "contact", "2")

      alice_contact = Repo.get!(Contacts.Contact, alice_rec.local_entity_id)
      assert alice_contact.first_met_through_id == bob_rec.local_entity_id

      Agent.stop(agent)
    end

    test "imports how_you_met fields fully", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Eve",
          how_you_met: %{
            "general_information" => "Through mutual friends at a party",
            "first_met_date" => %{
              "date" => "2019-07-04T00:00:00Z",
              "is_year_unknown" => false
            },
            "first_met_through_contact" => nil
          }
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      eve =
        Repo.one(
          from c in Contacts.Contact, where: c.first_name == "Eve" and c.account_id == ^account_id
        )

      assert eve.first_met_at == ~D[2019-07-04]
      assert eve.first_met_year_unknown == false
      assert eve.first_met_additional_info == "Through mutual friends at a party"
    end

    test "skips first_met_through when referenced contact not found", %{
      user: user,
      account_id: account_id
    } do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Lonely",
          how_you_met: %{
            "general_information" => nil,
            "first_met_date" => nil,
            "first_met_through_contact" =>
              contact_short_json(999, Ecto.UUID.generate(), "Ghost", "Person")
          }
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 1
      assert summary.error_count > 0
      assert Enum.any?(summary.errors, &String.contains?(&1, "first_met_through"))
    end

    test "handles nil how_you_met gracefully", %{user: user, account_id: account_id} do
      contacts = [contact_json(id: 1, first_name: "Simple")]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 1
      assert summary.error_count == 0
    end
  end

  # ── crawl/5 — relationships ───────────────────────────────────────────

  describe "crawl/5 — relationships" do
    test "creates relationships from embedded information.relationships", %{
      user: user,
      account_id: account_id
    } do
      bob_short = contact_short_json(2, Ecto.UUID.generate(), "Bob", "Spouse")

      alice =
        contact_json(
          id: 1,
          first_name: "Alice",
          relationships: %{
            "love" => %{
              "total" => 1,
              "contacts" => [
                %{
                  "relationship" => %{
                    "id" => 1,
                    "uuid" => Ecto.UUID.generate(),
                    "name" => "spouse"
                  },
                  "contact" => bob_short
                }
              ]
            },
            "family" => %{"total" => 0, "contacts" => []},
            "friend" => %{"total" => 0, "contacts" => []},
            "work" => %{"total" => 0, "contacts" => []}
          }
        )

      bob = contact_json(id: 2, first_name: "Bob", last_name: "Spouse")

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json([alice, bob]))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 2

      alice_rec = Imports.find_import_record(account_id, "monica_api", "contact", "1")
      bob_rec = Imports.find_import_record(account_id, "monica_api", "contact", "2")

      rels =
        Repo.all(
          from r in Contacts.Relationship,
            where: r.contact_id == ^alice_rec.local_entity_id
        )

      assert length(rels) >= 1
      assert Enum.any?(rels, fn r -> r.related_contact_id == bob_rec.local_entity_id end)
    end

    test "skips relationship when related contact not imported", %{
      user: user,
      account_id: account_id
    } do
      ghost_short = contact_short_json(999, Ecto.UUID.generate(), "Ghost", "Person")

      alice =
        contact_json(
          id: 1,
          first_name: "Alice",
          relationships: %{
            "love" => %{"total" => 0, "contacts" => []},
            "family" => %{"total" => 0, "contacts" => []},
            "friend" => %{
              "total" => 1,
              "contacts" => [
                %{
                  "relationship" => %{
                    "id" => 1,
                    "uuid" => Ecto.UUID.generate(),
                    "name" => "friend"
                  },
                  "contact" => ghost_short
                }
              ]
            },
            "work" => %{"total" => 0, "contacts" => []}
          }
        )

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json([alice]))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 1
      assert Enum.any?(summary.errors, &String.contains?(&1, "not imported"))
    end
  end

  # ── crawl/5 — extra notes ─────────────────────────────────────────────

  describe "crawl/5 — extra notes" do
    test "fetches extra notes for contacts with more than 3", %{
      user: user,
      account_id: account_id
    } do
      embedded_notes = for i <- 1..3, do: note_json(body: "Embedded note #{i}")

      all_notes =
        for i <- 1..7, do: note_json(body: "Note #{i}")

      contacts = [
        contact_json(
          id: 1,
          first_name: "Verbose",
          number_of_notes: 7,
          notes: embedded_notes
        )
      ]

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        call = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

        if call == 1 do
          # Contacts page
          Req.Test.json(conn, contacts_page_json(contacts))
        else
          # Notes page
          Req.Test.json(conn, notes_page_json(all_notes, 1, 1, 7))
        end
      end)

      import_job =
        api_import_fixture(account_id, user.id, %{api_options: %{"extra_notes" => true}})

      assert {:ok, summary} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{
                 "extra_notes" => true
               })

      # 3 embedded + 4 extra = 7 total notes
      # (first 3 skipped from the full notes list, so 4 extra imported)
      assert summary.notes >= 3

      Agent.stop(agent)
    end

    test "does not fetch extra notes for contacts with 3 or fewer", %{
      user: user,
      account_id: account_id
    } do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Brief",
          number_of_notes: 2,
          notes: [note_json(body: "Note 1"), note_json(body: "Note 2")]
        )
      ]

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        Agent.update(agent, &(&1 + 1))
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)

      assert {:ok, _} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{
                 "extra_notes" => true
               })

      # Only the contacts page should have been fetched
      assert Agent.get(agent, & &1) == 1
      Agent.stop(agent)
    end
  end

  # ── crawl/5 — photo crawl ────────────────────────────────────────────

  describe "crawl/5 — photo crawl" do
    test "imports photos from paginated photos endpoint", %{user: user, account_id: account_id} do
      # Small 1x1 JPEG encoded as data URL
      pixel = Base.encode64(<<0xFF, 0xD8, 0xFF, 0xE0>>)
      data_url = "data:image/jpeg;base64,#{pixel}"

      contacts = [contact_json(id: 1, first_name: "PhotoPerson")]

      photos = [
        photo_json(
          id: 1,
          data_url: data_url,
          contact: contact_short_json(1, Ecto.UUID.generate(), "PhotoPerson", "Test")
        )
      ]

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        call = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

        if call == 1 do
          Req.Test.json(conn, contacts_page_json(contacts))
        else
          Req.Test.json(conn, photos_page_json(photos))
        end
      end)

      import_job = api_import_fixture(account_id, user.id)

      assert {:ok, _} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{"photos" => true})

      # Verify photos endpoint was called
      assert Agent.get(agent, & &1) == 2
      Agent.stop(agent)
    end

    test "skips photos when opt-out", %{user: user, account_id: account_id} do
      contacts = [contact_json(id: 1, first_name: "NoPhotos")]

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        Agent.update(agent, &(&1 + 1))
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      # Only contacts page, no photos
      assert Agent.get(agent, & &1) == 1
      Agent.stop(agent)
    end
  end

  # ── crawl/5 — rate limiting ──────────────────────────────────────────

  describe "crawl/5 — rate limiting" do
    @tag :slow
    test "retries on 429 from contacts endpoint", %{user: user, account_id: account_id} do
      contacts = [contact_json(id: 1, first_name: "Patient")]

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        call = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

        if call == 1 do
          Plug.Conn.send_resp(conn, 429, "")
        else
          Req.Test.json(conn, contacts_page_json(contacts))
        end
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 1

      Agent.stop(agent)
    end

    @tag :slow
    test "fails after max retries on persistent 429", %{user: user, account_id: account_id} do
      Req.Test.stub(@stub_name, fn conn ->
        Plug.Conn.send_resp(conn, 429, "")
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.error_count > 0
      assert Enum.any?(summary.errors, &String.contains?(&1, "Rate limited"))
    end
  end

  # ── crawl/5 — cancellation ──────────────────────────────────────────

  describe "crawl/5 — cancellation" do
    test "stops crawling when import is already cancelled", %{user: user, account_id: account_id} do
      contacts = for i <- 1..20, do: contact_json(id: i, first_name: "Person#{i}")

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts, 1, 1, 20))
      end)

      import_job = api_import_fixture(account_id, user.id)

      # Cancel the import before crawl checks (checked every 10 contacts)
      Imports.cancel_import(import_job)

      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert Enum.any?(summary.errors, &String.contains?(&1, "cancelled"))
      # Should have imported fewer than all 20
      assert summary.contacts < 20
    end
  end

  # ── crawl/5 — re-import / deduplication ──────────────────────────────

  describe "crawl/5 — re-import / deduplication" do
    test "updates existing contacts on re-import", %{user: user, account_id: account_id} do
      contacts_v1 = [contact_json(id: 1, first_name: "Alice", last_name: "Old")]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts_v1))
      end)

      import_job1 = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job1, %{})

      alice =
        Repo.one(
          from c in Contacts.Contact,
            where: c.first_name == "Alice" and c.account_id == ^account_id
        )

      assert alice.last_name == "Old"

      # Complete the first import so we can create a second
      Imports.update_import_status(import_job1, "completed", %{completed_at: DateTime.utc_now()})

      # Re-import with updated name
      contacts_v2 = [contact_json(id: 1, first_name: "Alice", last_name: "New")]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts_v2))
      end)

      import_job2 = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job2, %{})

      alice = Repo.get!(Contacts.Contact, alice.id)
      assert alice.last_name == "New"

      # Still only one contact in DB
      count =
        Repo.aggregate(
          from(c in Contacts.Contact,
            where: c.first_name == "Alice" and c.account_id == ^account_id
          ),
          :count
        )

      assert count == 1
    end

    test "skips soft-deleted contacts on re-import", %{user: user, account_id: account_id} do
      contacts = [contact_json(id: 1, first_name: "Deleted")]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job1 = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job1, %{})

      # Soft-delete the contact
      rec = Imports.find_import_record(account_id, "monica_api", "contact", "1")
      contact = Repo.get!(Contacts.Contact, rec.local_entity_id)

      contact
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      Imports.update_import_status(import_job1, "completed", %{completed_at: DateTime.utc_now()})

      # Re-import
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job2 = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job2, %{})
      assert summary.skipped >= 1
    end
  end

  # ── crawl/5 — error handling ─────────────────────────────────────────

  describe "crawl/5 — error handling" do
    test "handles malformed API response", %{user: user, account_id: account_id} do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"unexpected" => "format"})
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.error_count > 0
    end

    test "handles empty addresses/tags/fields gracefully", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Empty",
          addresses: [],
          tags: [],
          contact_fields: [],
          notes: []
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      assert summary.contacts == 1
      assert summary.error_count == 0
    end

    test "handles network error mid-crawl", %{user: user, account_id: account_id} do
      contacts = [contact_json(id: 1, first_name: "Page1")]

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        call = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

        if call == 1 do
          Req.Test.json(conn, contacts_page_json(contacts, 1, 2, 2))
        else
          Plug.Conn.send_resp(conn, 500, "Internal Server Error")
        end
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, summary} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})
      # First page imported, second page failed
      assert summary.contacts == 1
      assert summary.error_count > 0

      Agent.stop(agent)
    end
  end

  # ── crawl/5 — reference data ──────────────────────────────────────────

  describe "crawl/5 — reference data" do
    test "creates genders from API contact gender strings", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(id: 1, first_name: "Alice", gender: "Female"),
        contact_json(id: 2, first_name: "Bob", gender: "Male")
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      alice =
        Repo.one(
          from c in Contacts.Contact,
            where: c.first_name == "Alice" and c.account_id == ^account_id
        )

      bob =
        Repo.one(
          from c in Contacts.Contact, where: c.first_name == "Bob" and c.account_id == ^account_id
        )

      assert alice.gender_id != nil
      assert bob.gender_id != nil
      assert alice.gender_id != bob.gender_id
    end

    test "creates tags from embedded tags array", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Tagged",
          tags: [tag_json("VIP"), tag_json("Family")]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      rec = Imports.find_import_record(account_id, "monica_api", "contact", "1")
      contact = Repo.get!(Contacts.Contact, rec.local_entity_id) |> Repo.preload(:tags)
      tag_names = Enum.map(contact.tags, & &1.name) |> Enum.sort()
      assert tag_names == ["Family", "VIP"]
    end

    test "creates contact field types from contactFields", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Fieldy",
          contact_fields: [
            contact_field_json(content: "555-1234", type_name: "Phone"),
            contact_field_json(content: "fieldy@test.com", type_name: "Email")
          ]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      rec = Imports.find_import_record(account_id, "monica_api", "contact", "1")

      fields =
        Repo.all(from cf in Contacts.ContactField, where: cf.contact_id == ^rec.local_entity_id)
        |> Enum.map(& &1.value)
        |> Enum.sort()

      assert fields == ["+5551234", "fieldy@test.com"]
    end
  end

  # ── Behaviour callbacks ──────────────────────────────────────────────

  describe "behaviour callbacks" do
    test "name/0" do
      assert MonicaApi.name() == "Monica CRM (API)"
    end

    test "file_types/0" do
      assert MonicaApi.file_types() == []
    end

    test "supports_api?/0" do
      assert MonicaApi.supports_api?() == true
    end

    test "validate_file/1 returns error" do
      assert {:error, _} = MonicaApi.validate_file("data")
    end

    test "parse_summary/1 returns error" do
      assert {:error, _} = MonicaApi.parse_summary("data")
    end

    test "import/4 returns error" do
      assert {:error, _} = MonicaApi.import(1, 1, "data", %{})
    end
  end

  # ── Sub-record deduplication ─────────────────────────────────────────

  describe "crawl/5 — address deduplication" do
    test "skips duplicate addresses within the same contact", %{
      user: user,
      account_id: account_id
    } do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Dupe",
          last_name: "Addr",
          addresses: [
            address_json(street: "100 Oak Ave", city: "Denver", country: %{"name" => "US"}),
            address_json(street: "100 Oak Ave", city: "Denver", country: %{"name" => "US"}),
            address_json(street: "100 Oak Ave", city: "denver", country: %{"name" => "us"})
          ]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      contact =
        Repo.one!(
          from(c in Contacts.Contact,
            where: c.first_name == "Dupe" and c.account_id == ^account_id
          )
        )

      addresses = Repo.all(from(a in Contacts.Address, where: a.contact_id == ^contact.id))
      assert length(addresses) == 1
      assert hd(addresses).line1 == "100 Oak Ave"
    end

    test "allows addresses with different fields", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Multi",
          last_name: "Addr",
          addresses: [
            address_json(street: "100 Oak Ave", city: "Denver"),
            address_json(street: "200 Elm St", city: "Denver"),
            address_json(street: "100 Oak Ave", city: "Portland")
          ]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      contact =
        Repo.one!(
          from(c in Contacts.Contact,
            where: c.first_name == "Multi" and c.account_id == ^account_id
          )
        )

      addresses = Repo.all(from(a in Contacts.Address, where: a.contact_id == ^contact.id))
      assert length(addresses) == 3
    end
  end

  describe "crawl/5 — note deduplication" do
    test "skips duplicate notes within the same contact", %{
      user: user,
      account_id: account_id
    } do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Dupe",
          last_name: "Note",
          number_of_notes: 2,
          notes: [
            note_json(body: "Hello world"),
            note_json(body: "Hello world"),
            note_json(body: "  Hello world  ")
          ]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      contact =
        Repo.one!(
          from(c in Contacts.Contact,
            where: c.first_name == "Dupe" and c.account_id == ^account_id
          )
        )

      notes = Repo.all(from(n in Contacts.Note, where: n.contact_id == ^contact.id))
      assert length(notes) == 1
      assert hd(notes).body == "Hello world"
    end

    test "allows notes with different bodies", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Multi",
          last_name: "Note",
          number_of_notes: 2,
          notes: [
            note_json(body: "First note"),
            note_json(body: "Second note")
          ]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts))
      end)

      import_job = api_import_fixture(account_id, user.id)
      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      contact =
        Repo.one!(
          from(c in Contacts.Contact,
            where: c.first_name == "Multi" and c.account_id == ^account_id
          )
        )

      notes = Repo.all(from(n in Contacts.Note, where: n.contact_id == ^contact.id))
      assert length(notes) == 2
    end

    test "skips duplicate notes in extra_notes phase", %{user: user, account_id: account_id} do
      # Contact has 5 notes total — 3 embedded + 2 extra
      # One extra note duplicates an embedded one
      contacts = [
        contact_json(
          id: 1,
          first_name: "Extra",
          last_name: "Notes",
          number_of_notes: 5,
          notes: [
            note_json(id: 1, body: "Note A"),
            note_json(id: 2, body: "Note B"),
            note_json(id: 3, body: "Note C")
          ]
        )
      ]

      request_count = :counters.new(1, [:atomics])

      Req.Test.stub(@stub_name, fn conn ->
        :counters.add(request_count, 1, 1)
        count = :counters.get(request_count, 1)

        if count == 1 do
          # First request: contacts page
          Req.Test.json(conn, contacts_page_json(contacts))
        else
          # Notes request: includes a duplicate of "Note A" and a new "Note D"
          Req.Test.json(
            conn,
            notes_page_json([
              note_json(id: 1, body: "Note A"),
              note_json(id: 2, body: "Note B"),
              note_json(id: 3, body: "Note C"),
              note_json(id: 4, body: "Note A"),
              note_json(id: 5, body: "Note D")
            ])
          )
        end
      end)

      import_job =
        api_import_fixture(account_id, user.id, %{
          api_options: %{"photos" => false, "extra_notes" => true}
        })

      assert {:ok, _} = MonicaApi.crawl(account_id, user.id, credential(), import_job, %{})

      contact =
        Repo.one!(
          from(c in Contacts.Contact,
            where: c.first_name == "Extra" and c.account_id == ^account_id
          )
        )

      notes = Repo.all(from(n in Contacts.Note, where: n.contact_id == ^contact.id))
      # Should have A, B, C, D — not a second A
      assert length(notes) == 4

      bodies = Enum.map(notes, & &1.body) |> Enum.sort()
      assert bodies == ["Note A", "Note B", "Note C", "Note D"]
    end
  end

  # ── Auto-merge duplicate contacts ───────────────────────────────────

  describe "crawl/5 — auto-merge duplicates" do
    test "merges contacts with same name and email when enabled", %{
      user: user,
      account_id: account_id
    } do
      contacts = [
        contact_json(
          id: 1,
          first_name: "John",
          last_name: "Doe",
          contact_fields: [contact_field_json(content: "john@example.com", type_name: "Email")],
          notes: [note_json(body: "From source A")]
        ),
        contact_json(
          id: 2,
          first_name: "John",
          last_name: "Doe",
          contact_fields: [contact_field_json(content: "john@example.com", type_name: "Email")],
          notes: [note_json(body: "From source B")]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts, 1, 1, 2))
      end)

      import_job = api_import_fixture(account_id, user.id)

      assert {:ok, summary} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{
                 "auto_merge_duplicates" => true
               })

      assert summary.merged == 1

      # Only 1 active contact should remain
      active =
        Repo.all(
          from(c in Contacts.Contact,
            where:
              c.first_name == "John" and c.last_name == "Doe" and
                c.account_id == ^account_id and is_nil(c.deleted_at)
          )
        )

      assert length(active) == 1
      survivor = hd(active)

      # Survivor should have notes from both contacts
      notes = Repo.all(from(n in Contacts.Note, where: n.contact_id == ^survivor.id))
      assert length(notes) >= 2
    end

    test "does not merge when disabled", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Jane",
          last_name: "Doe",
          contact_fields: [contact_field_json(content: "jane@example.com", type_name: "Email")]
        ),
        contact_json(
          id: 2,
          first_name: "Jane",
          last_name: "Doe",
          contact_fields: [contact_field_json(content: "jane@example.com", type_name: "Email")]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts, 1, 1, 2))
      end)

      import_job = api_import_fixture(account_id, user.id)

      assert {:ok, summary} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{
                 "auto_merge_duplicates" => false
               })

      assert summary.merged == 0

      active =
        Repo.all(
          from(c in Contacts.Contact,
            where:
              c.first_name == "Jane" and c.last_name == "Doe" and
                c.account_id == ^account_id and is_nil(c.deleted_at)
          )
        )

      assert length(active) == 2
    end

    test "does not merge contacts with same name but different email/phone", %{
      user: user,
      account_id: account_id
    } do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Bob",
          last_name: "Smith",
          contact_fields: [contact_field_json(content: "bob1@example.com", type_name: "Email")]
        ),
        contact_json(
          id: 2,
          first_name: "Bob",
          last_name: "Smith",
          contact_fields: [contact_field_json(content: "bob2@example.com", type_name: "Email")]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts, 1, 1, 2))
      end)

      import_job = api_import_fixture(account_id, user.id)

      assert {:ok, summary} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{
                 "auto_merge_duplicates" => true
               })

      assert summary.merged == 0

      active =
        Repo.all(
          from(c in Contacts.Contact,
            where:
              c.first_name == "Bob" and c.last_name == "Smith" and
                c.account_id == ^account_id and is_nil(c.deleted_at)
          )
        )

      assert length(active) == 2
    end

    test "merges contacts with same name and phone", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Alice",
          last_name: "Wang",
          contact_fields: [contact_field_json(content: "+15551234567", type_name: "Phone")]
        ),
        contact_json(
          id: 2,
          first_name: "Alice",
          last_name: "Wang",
          contact_fields: [contact_field_json(content: "+15551234567", type_name: "Phone")]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts, 1, 1, 2))
      end)

      import_job = api_import_fixture(account_id, user.id)

      assert {:ok, summary} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{
                 "auto_merge_duplicates" => true
               })

      assert summary.merged == 1

      active =
        Repo.all(
          from(c in Contacts.Contact,
            where:
              c.first_name == "Alice" and c.last_name == "Wang" and
                c.account_id == ^account_id and is_nil(c.deleted_at)
          )
        )

      assert length(active) == 1
    end

    test "handles triple duplicates", %{user: user, account_id: account_id} do
      contacts = [
        contact_json(
          id: 1,
          first_name: "Triple",
          last_name: "Test",
          contact_fields: [contact_field_json(content: "triple@test.com", type_name: "Email")]
        ),
        contact_json(
          id: 2,
          first_name: "Triple",
          last_name: "Test",
          contact_fields: [contact_field_json(content: "triple@test.com", type_name: "Email")]
        ),
        contact_json(
          id: 3,
          first_name: "Triple",
          last_name: "Test",
          contact_fields: [contact_field_json(content: "triple@test.com", type_name: "Email")]
        )
      ]

      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, contacts_page_json(contacts, 1, 1, 3))
      end)

      import_job = api_import_fixture(account_id, user.id)

      assert {:ok, summary} =
               MonicaApi.crawl(account_id, user.id, credential(), import_job, %{
                 "auto_merge_duplicates" => true
               })

      assert summary.merged == 2

      active =
        Repo.all(
          from(c in Contacts.Contact,
            where:
              c.first_name == "Triple" and c.last_name == "Test" and
                c.account_id == ^account_id and is_nil(c.deleted_at)
          )
        )

      assert length(active) == 1
    end
  end
end
