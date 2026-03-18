defmodule KithWeb.UserLive.ConfirmationTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kith.AccountsFixtures

  alias Kith.Accounts

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "Confirm user" do
    test "renders confirmation page with valid token", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(
            %{user | confirmed_at: nil},
            url
          )
        end)

      {:ok, _lv, html} = live(conn, ~p"/users/confirm/#{token}")
      assert html =~ "Confirm your account"
    end

    test "renders confirmation page even with invalid token", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/confirm/invalid-token")
      assert html =~ "Confirm your account"
    end
  end
end
