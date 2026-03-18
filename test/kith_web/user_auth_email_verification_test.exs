defmodule KithWeb.UserAuthEmailVerificationTest do
  # async: false because we modify global Application config
  use KithWeb.ConnCase, async: false

  import Ecto.Query
  import Kith.AccountsFixtures
  alias KithWeb.UserAuth

  describe "require_confirmed_user/2 with double optin enabled" do
    setup do
      # Create users before enabling double optin so they get auto-confirmed
      confirmed_user = user_fixture()
      unconfirmed_user = user_fixture()

      Application.put_env(:kith, :signup_double_optin, true)
      on_exit(fn -> Application.put_env(:kith, :signup_double_optin, false) end)

      Kith.Repo.update_all(
        from(u in Kith.Accounts.User, where: u.id == ^unconfirmed_user.id),
        set: [confirmed_at: nil]
      )

      unconfirmed_user = %{unconfirmed_user | confirmed_at: nil}
      %{confirmed_user: confirmed_user, unconfirmed_user: unconfirmed_user}
    end

    test "redirects unconfirmed users", %{conn: conn, unconfirmed_user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> UserAuth.fetch_current_scope_for_user([])
        |> fetch_flash()
        |> UserAuth.require_confirmed_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/confirm-email"
    end

    test "passes through confirmed users", %{conn: conn, confirmed_user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> UserAuth.fetch_current_scope_for_user([])
        |> fetch_flash()
        |> UserAuth.require_confirmed_user([])

      refute conn.halted
    end
  end

  describe "require_confirmed_user/2 with double optin disabled" do
    test "always passes through even for unconfirmed users", %{conn: conn} do
      user = user_fixture()

      Kith.Repo.update_all(
        from(u in Kith.Accounts.User, where: u.id == ^user.id),
        set: [confirmed_at: nil]
      )

      unconfirmed_user = %{user | confirmed_at: nil}

      conn =
        conn
        |> log_in_user(unconfirmed_user)
        |> UserAuth.fetch_current_scope_for_user([])
        |> UserAuth.require_confirmed_user([])

      refute conn.halted
    end
  end
end
