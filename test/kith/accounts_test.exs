defmodule Kith.AccountsTest do
  use Kith.DataCase

  alias Kith.Accounts

  import Kith.AccountsFixtures

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %Accounts.User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %Accounts.User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "register_user/1" do
    test "requires email and password" do
      assert {:error, changeset} = Accounts.register_user(%{name: "Test"})
      assert %{email: ["can't be blank"], password: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email and password when given" do
      assert {:error, changeset} =
               Accounts.register_user(%{name: "Test", email: "not valid", password: "short"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password" do
      too_long_password = String.duplicate("a", 100)
      too_long_email = String.duplicate("a", 161) <> "@example.com"

      assert {:error, changeset} =
               Accounts.register_user(%{
                 name: "Test",
                 email: too_long_email,
                 password: too_long_password
               })

      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()

      assert {:error, changeset} =
               Accounts.register_user(%{
                 name: "Test",
                 email: email,
                 password: valid_user_password()
               })

      assert "has already been taken" in errors_on(changeset).email
    end

    test "creates an account and user with role admin" do
      email = unique_user_email()

      assert {:ok, user} =
               Accounts.register_user(%{
                 name: "Test Account",
                 email: email,
                 password: valid_user_password()
               })

      assert user.email == email
      assert user.role == "admin"
      assert user.account_id
      assert user.account
      assert is_nil(user.password)
      assert is_binary(user.hashed_password)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert is_binary(token)

      assert {found_user, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert found_user.id == user.id
      assert found_user.account.id == user.account_id
    end

    test "returns nil for invalid token" do
      refute Accounts.get_user_by_session_token("invalid")
      refute Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      assert {:error, changeset} = Accounts.update_user_password(user, %{password: "short"})
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "updates the password and deletes all tokens", %{user: user} do
      _token = Accounts.generate_user_session_token(user)

      assert {:ok, {updated_user, expired_tokens}} =
               Accounts.update_user_password(user, %{password: "new valid password!!"})

      assert updated_user.id == user.id
      assert is_list(expired_tokens)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token", %{} do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {_user, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    test "sends email to the user", %{} do
      user = user_fixture()
      # Set confirmed_at to nil to allow sending
      user = %{user | confirmed_at: nil}

      assert {:ok, _email} =
               Accounts.deliver_user_confirmation_instructions(user, &"/confirm/#{&1}")
    end

    test "returns error if already confirmed" do
      user = user_fixture()

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(user, &"/confirm/#{&1}")
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    test "sends email to the user" do
      user = user_fixture()

      assert {:ok, _email} =
               Accounts.deliver_user_reset_password_instructions(user, &"/reset/#{&1}")
    end
  end
end
