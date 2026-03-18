defmodule KithWeb.UserLive.SettingsTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kith.AccountsFixtures

  @tag token_authenticated_at: DateTime.utc_now(:second)
  setup :register_and_log_in_user

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Account Settings"
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert flash["error"] =~ "You must log in"
    end
  end

  describe "update email form" do
    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", user: %{email: new_email})
        |> render_submit()

      assert result =~ "A link to confirm your email"
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{user: %{email: "bad"}})

      assert result =~ "must have the @ sign"
    end
  end

  describe "update password form" do
    test "validates password", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{user: %{password: "short", password_confirmation: "mismatch"}})

      assert result =~ "should be at least 12 character"
      assert result =~ "does not match password"
    end
  end
end
