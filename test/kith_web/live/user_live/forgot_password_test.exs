defmodule KithWeb.UserLive.ForgotPasswordTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kith.AccountsFixtures

  describe "Forgot password page" do
    test "renders the form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset-password")
      assert html =~ "Forgot your password?"
      assert html =~ "Send password reset instructions"
    end

    test "sends reset email and navigates to login", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      lv
      |> form("#reset_password_form", user: %{email: user.email})
      |> render_submit()

      flash = assert_redirect(lv, ~p"/users/log-in")
      assert flash["info"] =~ "If your email is in our system"
    end

    test "does not reveal if email exists", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      lv
      |> form("#reset_password_form", user: %{email: "nobody@example.com"})
      |> render_submit()

      flash = assert_redirect(lv, ~p"/users/log-in")
      assert flash["info"] =~ "If your email is in our system"
    end
  end
end
