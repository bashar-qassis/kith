defmodule KithWeb.UserLive.ConfirmEmailPendingTest do
  use KithWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Kith.AccountsFixtures

  setup do
    # Create an unconfirmed user by setting confirmed_at to nil after creation
    user = user_fixture()

    Kith.Repo.update_all(
      from(u in Kith.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: nil]
    )

    user = %{user | confirmed_at: nil}
    %{user: user}
  end

  describe "Confirm email pending page" do
    test "renders the pending page for unconfirmed users", %{conn: conn, user: user} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/confirm-email")

      assert html =~ "Check your email"
      assert html =~ user.email
      assert html =~ "Resend verification email"
    end

    test "redirects to home if user is already confirmed", %{conn: conn} do
      # Explicitly create a confirmed user (not relying on auto-confirm config)
      confirmed_user = user_fixture()

      result =
        conn
        |> log_in_user(confirmed_user)
        |> live(~p"/users/confirm-email")

      # redirect/2 in mount causes a full HTTP redirect
      assert {:error, {:redirect, %{to: "/"}}} = result
    end

    test "redirects to login if not authenticated", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/confirm-email")
      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/log-in"
    end
  end

  describe "resend verification email" do
    test "sends a new confirmation email", %{conn: conn, user: user} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/confirm-email")

      result = render_click(lv, "resend")
      assert result =~ "Verification email sent"
    end
  end
end
