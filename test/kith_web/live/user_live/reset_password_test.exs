defmodule KithWeb.UserLive.ResetPasswordTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kith.AccountsFixtures

  alias Kith.Accounts

  setup do
    user = user_fixture()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(user, url)
      end)

    %{user: user, token: token}
  end

  describe "Reset password page" do
    test "renders reset password form with valid token", %{conn: conn, token: token} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset-password/#{token}")
      assert html =~ "Reset password"
    end

    test "navigates with error for invalid token", %{conn: conn} do
      # push_navigate in mount causes a live_redirect during static render
      assert {:error, {:live_redirect, %{to: "/users/reset-password", flash: flash}}} =
               live(conn, ~p"/users/reset-password/invalid-token")

      assert flash["error"] =~ "Reset password link is invalid or it has expired"
    end
  end

  describe "reset password" do
    test "resets password with valid token and data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      lv
      |> form("#reset_password_form",
        user: %{password: "new valid password!!", password_confirmation: "new valid password!!"}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/users/log-in")
    end

    test "validates password on change", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      result =
        lv
        |> element("#reset_password_form")
        |> render_change(user: %{password: "short", password_confirmation: "mismatch"})

      assert result =~ "should be at least 12 character"
    end

    test "shows error for invalid password on submit", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      result =
        lv
        |> form("#reset_password_form",
          user: %{password: "short", password_confirmation: "short"}
        )
        |> render_submit()

      assert result =~ "should be at least 12 character"
    end
  end
end
