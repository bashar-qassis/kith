defmodule Kith.DuplicateDetectionTest do
  use Kith.DataCase, async: true

  import Kith.Factory

  alias Kith.DuplicateDetection

  describe "list_candidates/2" do
    test "returns pending candidates by default" do
      {account, _user} = setup_account()
      contact1 = insert(:contact, account: account)
      contact2 = insert(:contact, account: account)

      candidate =
        insert(:duplicate_candidate,
          account: account,
          contact: contact1,
          duplicate_contact: contact2,
          status: "pending"
        )

      assert [returned] = DuplicateDetection.list_candidates(account.id)
      assert returned.id == candidate.id
    end

    test "filters by status" do
      {account, _user} = setup_account()
      contact1 = insert(:contact, account: account)
      contact2 = insert(:contact, account: account)
      contact3 = insert(:contact, account: account)

      insert(:duplicate_candidate,
        account: account,
        contact: contact1,
        duplicate_contact: contact2,
        status: "pending"
      )

      dismissed =
        insert(:duplicate_candidate,
          account: account,
          contact: contact1,
          duplicate_contact: contact3,
          status: "dismissed",
          resolved_at: DateTime.utc_now(:second)
        )

      assert [returned] = DuplicateDetection.list_candidates(account.id, status: "dismissed")
      assert returned.id == dismissed.id
    end

    test "does not return candidates from another account" do
      {account1, _user1} = setup_account()
      {account2, _user2} = setup_account()
      c1 = insert(:contact, account: account1)
      c2 = insert(:contact, account: account1)
      c3 = insert(:contact, account: account2)
      c4 = insert(:contact, account: account2)

      insert(:duplicate_candidate, account: account1, contact: c1, duplicate_contact: c2)
      insert(:duplicate_candidate, account: account2, contact: c3, duplicate_contact: c4)

      assert [candidate] = DuplicateDetection.list_candidates(account1.id)
      assert candidate.account_id == account1.id
    end

    test "orders by score descending" do
      {account, _user} = setup_account()
      c1 = insert(:contact, account: account)
      c2 = insert(:contact, account: account)
      c3 = insert(:contact, account: account)

      insert(:duplicate_candidate,
        account: account,
        contact: c1,
        duplicate_contact: c2,
        score: 0.7
      )

      insert(:duplicate_candidate,
        account: account,
        contact: c1,
        duplicate_contact: c3,
        score: 0.95
      )

      candidates = DuplicateDetection.list_candidates(account.id)
      scores = Enum.map(candidates, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "preloads contact and duplicate_contact" do
      {account, _user} = setup_account()
      c1 = insert(:contact, account: account)
      c2 = insert(:contact, account: account)

      insert(:duplicate_candidate, account: account, contact: c1, duplicate_contact: c2)

      assert [candidate] = DuplicateDetection.list_candidates(account.id)
      assert candidate.contact.id == c1.id
      assert candidate.duplicate_contact.id == c2.id
    end
  end

  describe "get_candidate!/2" do
    test "returns candidate by id scoped to account" do
      {account, _user} = setup_account()
      c1 = insert(:contact, account: account)
      c2 = insert(:contact, account: account)

      candidate =
        insert(:duplicate_candidate, account: account, contact: c1, duplicate_contact: c2)

      fetched = DuplicateDetection.get_candidate!(account.id, candidate.id)
      assert fetched.id == candidate.id
    end

    test "raises for candidate in another account" do
      {account1, _user1} = setup_account()
      {account2, _user2} = setup_account()
      c1 = insert(:contact, account: account1)
      c2 = insert(:contact, account: account1)

      candidate =
        insert(:duplicate_candidate, account: account1, contact: c1, duplicate_contact: c2)

      assert_raise Ecto.NoResultsError, fn ->
        DuplicateDetection.get_candidate!(account2.id, candidate.id)
      end
    end

    test "preloads contact and duplicate_contact" do
      {account, _user} = setup_account()
      c1 = insert(:contact, account: account)
      c2 = insert(:contact, account: account)

      candidate =
        insert(:duplicate_candidate, account: account, contact: c1, duplicate_contact: c2)

      fetched = DuplicateDetection.get_candidate!(account.id, candidate.id)
      assert fetched.contact.id == c1.id
      assert fetched.duplicate_contact.id == c2.id
    end
  end

  describe "dismiss_candidate/1" do
    test "sets status to dismissed and resolved_at" do
      {account, _user} = setup_account()
      c1 = insert(:contact, account: account)
      c2 = insert(:contact, account: account)

      candidate =
        insert(:duplicate_candidate, account: account, contact: c1, duplicate_contact: c2)

      assert {:ok, dismissed} = DuplicateDetection.dismiss_candidate(candidate)
      assert dismissed.status == "dismissed"
      assert dismissed.resolved_at != nil
    end
  end

  describe "mark_merged/1" do
    test "sets status to merged and resolved_at" do
      {account, _user} = setup_account()
      c1 = insert(:contact, account: account)
      c2 = insert(:contact, account: account)

      candidate =
        insert(:duplicate_candidate, account: account, contact: c1, duplicate_contact: c2)

      assert {:ok, merged} = DuplicateDetection.mark_merged(candidate)
      assert merged.status == "merged"
      assert merged.resolved_at != nil
    end
  end

  describe "pending_count/1" do
    test "returns count of pending candidates" do
      {account, _user} = setup_account()
      c1 = insert(:contact, account: account)
      c2 = insert(:contact, account: account)
      c3 = insert(:contact, account: account)

      insert(:duplicate_candidate,
        account: account,
        contact: c1,
        duplicate_contact: c2,
        status: "pending"
      )

      insert(:duplicate_candidate,
        account: account,
        contact: c1,
        duplicate_contact: c3,
        status: "pending"
      )

      assert DuplicateDetection.pending_count(account.id) == 2
    end

    test "excludes non-pending candidates" do
      {account, _user} = setup_account()
      c1 = insert(:contact, account: account)
      c2 = insert(:contact, account: account)
      c3 = insert(:contact, account: account)

      insert(:duplicate_candidate,
        account: account,
        contact: c1,
        duplicate_contact: c2,
        status: "pending"
      )

      insert(:duplicate_candidate,
        account: account,
        contact: c1,
        duplicate_contact: c3,
        status: "dismissed",
        resolved_at: DateTime.utc_now(:second)
      )

      assert DuplicateDetection.pending_count(account.id) == 1
    end

    test "returns 0 when no pending candidates" do
      {account, _user} = setup_account()
      assert DuplicateDetection.pending_count(account.id) == 0
    end

    test "does not count candidates from another account" do
      {account1, _user1} = setup_account()
      {account2, _user2} = setup_account()

      c1 = insert(:contact, account: account2)
      c2 = insert(:contact, account: account2)
      insert(:duplicate_candidate, account: account2, contact: c1, duplicate_contact: c2)

      assert DuplicateDetection.pending_count(account1.id) == 0
    end
  end
end
