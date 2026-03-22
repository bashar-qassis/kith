defmodule Kith.ImmichReviewTest do
  use Kith.DataCase, async: true

  alias Kith.Contacts
  alias Kith.Contacts.{Contact, ImmichCandidate}
  alias Kith.Accounts.Account
  alias Kith.Repo

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup do
    user = user_fixture()
    account = Repo.get!(Account, user.account_id)
    contact = contact_fixture(account.id, %{first_name: "Alice", last_name: "Smith"})
    %{account: account, contact: contact}
  end

  describe "list_needs_review/1" do
    test "returns contacts with needs_review status", %{account: account, contact: contact} do
      contact
      |> Contact.update_changeset(%{immich_status: "needs_review"})
      |> Repo.update!()

      results = Contacts.list_needs_review(account.id)
      assert length(results) == 1
      assert hd(results).id == contact.id
    end

    test "excludes contacts with other statuses", %{account: account} do
      assert Contacts.list_needs_review(account.id) == []
    end
  end

  describe "count_needs_review/1" do
    test "returns correct count", %{account: account, contact: contact} do
      assert Contacts.count_needs_review(account.id) == 0

      contact
      |> Contact.update_changeset(%{immich_status: "needs_review"})
      |> Repo.update!()

      assert Contacts.count_needs_review(account.id) == 1
    end
  end

  describe "confirm_immich_link/3" do
    test "sets status to linked and stores person data", %{contact: contact} do
      {:ok, updated} =
        Contacts.confirm_immich_link(
          contact,
          "immich-uuid-1",
          "https://immich.example.com/people/immich-uuid-1"
        )

      assert updated.immich_status == "linked"
      assert updated.immich_person_id == "immich-uuid-1"
      assert updated.immich_person_url == "https://immich.example.com/people/immich-uuid-1"
    end
  end

  describe "unlink_immich/1" do
    test "clears all Immich data", %{contact: contact} do
      {:ok, linked} =
        contact
        |> Contact.update_changeset(%{
          immich_status: "linked",
          immich_person_id: "uuid-1",
          immich_person_url: "https://immich.example.com/people/uuid-1"
        })
        |> Repo.update()

      {:ok, unlinked} = Contacts.unlink_immich(linked)
      assert unlinked.immich_status == "unlinked"
      assert unlinked.immich_person_id == nil
      assert unlinked.immich_person_url == nil
    end
  end

  describe "reject_immich_candidate/1" do
    test "marks candidate as rejected", %{account: account, contact: contact} do
      {:ok, candidate} =
        %ImmichCandidate{}
        |> ImmichCandidate.changeset(%{
          account_id: account.id,
          contact_id: contact.id,
          immich_photo_id: "uuid-1",
          immich_server_url: "https://immich.example.com",
          thumbnail_url: "https://immich.example.com/api/people/uuid-1/thumbnail",
          suggested_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: "pending"
        })
        |> Repo.insert()

      # Set contact to needs_review
      contact
      |> Contact.update_changeset(%{immich_status: "needs_review"})
      |> Repo.update!()

      Contacts.reject_immich_candidate(candidate)

      reloaded = Repo.get!(ImmichCandidate, candidate.id)
      assert reloaded.status == "rejected"
    end
  end

  describe "list_pending_candidates/2" do
    test "returns only pending candidates", %{account: account, contact: contact} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %ImmichCandidate{}
      |> ImmichCandidate.changeset(%{
        account_id: account.id,
        contact_id: contact.id,
        immich_photo_id: "uuid-pending",
        immich_server_url: "https://immich.example.com",
        thumbnail_url: "https://immich.example.com/thumb/1",
        suggested_at: now,
        status: "pending"
      })
      |> Repo.insert!()

      %ImmichCandidate{}
      |> ImmichCandidate.changeset(%{
        account_id: account.id,
        contact_id: contact.id,
        immich_photo_id: "uuid-rejected",
        immich_server_url: "https://immich.example.com",
        thumbnail_url: "https://immich.example.com/thumb/2",
        suggested_at: now,
        status: "rejected"
      })
      |> Repo.insert!()

      pending = Contacts.list_pending_candidates(account.id, contact.id)
      assert length(pending) == 1
      assert hd(pending).immich_photo_id == "uuid-pending"
    end
  end
end
