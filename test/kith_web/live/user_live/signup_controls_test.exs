defmodule KithWeb.UserLive.SignupControlsTest do
  # async: false because we modify global Application config
  use KithWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "registration when DISABLE_SIGNUP=true" do
    setup do
      Application.put_env(:kith, :disable_signup, true)
      on_exit(fn -> Application.put_env(:kith, :disable_signup, false) end)
      :ok
    end

    test "redirects to login with error message", %{conn: conn} do
      {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/users/register")
    end

    test "hides signup link on login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")
      refute html =~ "Sign up"
    end
  end

  describe "registration when DISABLE_SIGNUP=false" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")
      assert html =~ "Register for an account"
    end

    test "shows signup link on login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")
      assert html =~ "Sign up"
    end
  end
end
