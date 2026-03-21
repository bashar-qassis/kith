defmodule Kith.DebtsTest do
  use Kith.DataCase, async: true

  import Kith.Factory

  alias Kith.Debts

  describe "list_debts/2" do
    test "returns debts for the contact scoped to account" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)

      assert [returned] = Debts.list_debts(account.id, contact.id)
      assert returned.id == debt.id
    end

    test "does not return debts from another contact" do
      {account, user} = setup_account()
      contact1 = insert(:contact, account: account)
      contact2 = insert(:contact, account: account)
      insert(:debt, account: account, contact: contact1, creator: user)
      insert(:debt, account: account, contact: contact2, creator: user)

      assert [debt] = Debts.list_debts(account.id, contact1.id)
      assert debt.contact_id == contact1.id
    end

    test "does not return debts from another account" do
      {account1, user1} = setup_account()
      {account2, user2} = setup_account()
      contact1 = insert(:contact, account: account1)
      contact2 = insert(:contact, account: account2)
      insert(:debt, account: account1, contact: contact1, creator: user1)
      insert(:debt, account: account2, contact: contact2, creator: user2)

      assert [debt] = Debts.list_debts(account1.id, contact1.id)
      assert debt.account_id == account1.id
    end

    test "preloads payments" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)
      insert(:debt_payment, debt: debt, account: account)

      assert [returned] = Debts.list_debts(account.id, contact.id)
      assert length(returned.payments) == 1
    end

    test "preloads currency" do
      {account, user} = setup_account()
      currency = Repo.get_by!(Kith.Contacts.Currency, code: "EUR")
      contact = insert(:contact, account: account)
      insert(:debt, account: account, contact: contact, creator: user, currency: currency)

      assert [returned] = Debts.list_debts(account.id, contact.id)
      assert returned.currency.code == "EUR"
    end
  end

  describe "get_debt!/2" do
    test "returns a debt by id scoped to account" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)

      fetched = Debts.get_debt!(account.id, debt.id)
      assert fetched.id == debt.id
    end

    test "raises for debt in another account" do
      {account1, user1} = setup_account()
      {account2, _user2} = setup_account()
      contact = insert(:contact, account: account1)
      debt = insert(:debt, account: account1, contact: contact, creator: user1)

      assert_raise Ecto.NoResultsError, fn ->
        Debts.get_debt!(account2.id, debt.id)
      end
    end

    test "preloads payments" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)
      insert(:debt_payment, debt: debt, account: account)

      fetched = Debts.get_debt!(account.id, debt.id)
      assert length(fetched.payments) == 1
    end

    test "preloads currency" do
      {account, user} = setup_account()
      currency = Repo.get_by!(Kith.Contacts.Currency, code: "GBP")
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user, currency: currency)

      fetched = Debts.get_debt!(account.id, debt.id)
      assert fetched.currency.symbol == "£"
    end
  end

  describe "create_debt/3" do
    test "creates a debt with valid attrs" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "title" => "Lunch money",
        "amount" => "50.00",
        "direction" => "owed_to_me",
        "contact_id" => contact.id
      }

      assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
      assert debt.title == "Lunch money"
      assert Decimal.equal?(debt.amount, Decimal.new("50.00"))
      assert debt.direction == "owed_to_me"
      assert debt.status == "active"
    end

    test "fails without title" do
      {account, user} = setup_account()

      attrs = %{"amount" => "50.00", "direction" => "owed_to_me"}
      assert {:error, changeset} = Debts.create_debt(account.id, user.id, attrs)
      assert errors_on(changeset).title
    end

    test "fails without amount" do
      {account, user} = setup_account()

      attrs = %{"title" => "Test", "direction" => "owed_to_me"}
      assert {:error, changeset} = Debts.create_debt(account.id, user.id, attrs)
      assert errors_on(changeset).amount
    end

    test "fails without direction" do
      {account, user} = setup_account()

      attrs = %{"title" => "Test", "amount" => "50.00"}
      assert {:error, changeset} = Debts.create_debt(account.id, user.id, attrs)
      assert errors_on(changeset).direction
    end

    test "fails with invalid direction" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "title" => "Test",
        "amount" => "50.00",
        "direction" => "gifted",
        "contact_id" => contact.id
      }

      assert {:error, changeset} = Debts.create_debt(account.id, user.id, attrs)
      assert errors_on(changeset).direction
    end

    test "fails with zero amount" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "title" => "Test",
        "amount" => "0",
        "direction" => "owed_to_me",
        "contact_id" => contact.id
      }

      assert {:error, changeset} = Debts.create_debt(account.id, user.id, attrs)
      assert errors_on(changeset).amount
    end

    test "defaults status to active" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "title" => "Test",
        "amount" => "25.00",
        "direction" => "owed_by_me",
        "contact_id" => contact.id
      }

      assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
      assert debt.status == "active"
    end

    test "inherits currency from contact when not specified" do
      {account, user} = setup_account()
      currency = Repo.get_by!(Kith.Contacts.Currency, code: "EUR")
      contact = insert(:contact, account: account, currency: currency)

      attrs = %{
        "title" => "Dinner",
        "amount" => "25.00",
        "direction" => "owed_to_me",
        "contact_id" => contact.id
      }

      assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
      assert debt.currency_id == currency.id
    end

    test "uses explicit currency_id when provided, ignoring contact default" do
      {account, user} = setup_account()
      eur = Repo.get_by!(Kith.Contacts.Currency, code: "EUR")
      gbp = Repo.get_by!(Kith.Contacts.Currency, code: "GBP")
      contact = insert(:contact, account: account, currency: eur)

      attrs = %{
        "title" => "Dinner",
        "amount" => "25.00",
        "direction" => "owed_to_me",
        "contact_id" => contact.id,
        "currency_id" => gbp.id
      }

      assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
      assert debt.currency_id == gbp.id
    end

    test "leaves currency nil when contact has no default and none specified" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)

      attrs = %{
        "title" => "Dinner",
        "amount" => "25.00",
        "direction" => "owed_to_me",
        "contact_id" => contact.id
      }

      assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
      assert is_nil(debt.currency_id)
    end
  end

  describe "update_debt/2" do
    test "updates debt attributes" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)

      assert {:ok, updated} = Debts.update_debt(debt, %{title: "Updated title", notes: "New note"})
      assert updated.title == "Updated title"
      assert updated.notes == "New note"
    end
  end

  describe "settle_debt/1" do
    test "sets status to settled and settled_at" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)

      assert {:ok, settled} = Debts.settle_debt(debt)
      assert settled.status == "settled"
      assert settled.settled_at != nil
    end
  end

  describe "write_off_debt/1" do
    test "sets status to written_off and settled_at" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)

      assert {:ok, written_off} = Debts.write_off_debt(debt)
      assert written_off.status == "written_off"
      assert written_off.settled_at != nil
    end
  end

  describe "add_payment/2" do
    test "adds a payment to a debt" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user, amount: Decimal.new("100.00"))

      attrs = %{"amount" => "30.00", "paid_at" => Date.utc_today() |> Date.to_string()}
      assert {:ok, payment} = Debts.add_payment(debt, attrs)
      assert Decimal.equal?(payment.amount, Decimal.new("30.00"))
    end

    test "auto-settles when payments reach the debt amount" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user, amount: Decimal.new("100.00"))

      attrs = %{"amount" => "100.00", "paid_at" => Date.utc_today() |> Date.to_string()}
      assert {:ok, _payment} = Debts.add_payment(debt, attrs)

      settled_debt = Debts.get_debt!(account.id, debt.id)
      assert settled_debt.status == "settled"
      assert settled_debt.settled_at != nil
    end

    test "auto-settles when payments exceed the debt amount" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user, amount: Decimal.new("50.00"))

      attrs = %{"amount" => "60.00", "paid_at" => Date.utc_today() |> Date.to_string()}
      assert {:ok, _payment} = Debts.add_payment(debt, attrs)

      settled_debt = Debts.get_debt!(account.id, debt.id)
      assert settled_debt.status == "settled"
    end

    test "does not auto-settle when payments are less than debt amount" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user, amount: Decimal.new("100.00"))

      attrs = %{"amount" => "40.00", "paid_at" => Date.utc_today() |> Date.to_string()}
      assert {:ok, _payment} = Debts.add_payment(debt, attrs)

      active_debt = Debts.get_debt!(account.id, debt.id)
      assert active_debt.status == "active"
    end

    test "fails without required fields" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)

      assert {:error, changeset} = Debts.add_payment(debt, %{})
      assert errors_on(changeset).amount
      assert errors_on(changeset).paid_at
    end
  end

  describe "outstanding_balance/1" do
    test "returns full amount when no payments" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user, amount: Decimal.new("100.00"))

      balance = Debts.outstanding_balance(debt)
      assert Decimal.equal?(balance, Decimal.new("100.00"))
    end

    test "subtracts payments from amount" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user, amount: Decimal.new("100.00"))
      insert(:debt_payment, debt: debt, account: account, amount: Decimal.new("30.00"))
      insert(:debt_payment, debt: debt, account: account, amount: Decimal.new("20.00"))

      balance = Debts.outstanding_balance(debt)
      assert Decimal.equal?(balance, Decimal.new("50.00"))
    end
  end

  describe "delete_payment/1" do
    test "deletes the payment" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)
      payment = insert(:debt_payment, debt: debt, account: account)

      assert {:ok, _} = Debts.delete_payment(payment)

      refreshed = Debts.get_debt!(account.id, debt.id)
      assert refreshed.payments == []
    end
  end

  describe "delete_debt/1" do
    test "deletes the debt" do
      {account, user} = setup_account()
      contact = insert(:contact, account: account)
      debt = insert(:debt, account: account, contact: contact, creator: user)

      assert {:ok, _} = Debts.delete_debt(debt)
      assert Debts.list_debts(account.id, contact.id) == []
    end
  end
end
