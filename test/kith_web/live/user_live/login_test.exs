defmodule KithWeb.UserLive.LoginTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kith.AccountsFixtures

  describe "user login page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Sign up"
      assert html =~ "Forgot password?"
    end

    test "renders reauthentication page if already logged in", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/log-in")

      assert html =~ "reauthenticate"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: valid_user_password()})

      conn = submit_form(form, conn)
      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error for invalid credentials", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form", user: %{email: "invalid@email.com", password: "invalid_password"})

      conn = submit_form(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
