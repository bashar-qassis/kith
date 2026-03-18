defmodule KithWeb.OAuthControllerTest do
  use KithWeb.ConnCase

  describe "request (GET /auth/:provider)" do
    test "redirects to login with error for unconfigured provider", %{conn: conn} do
      conn = get(conn, ~p"/auth/github")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not configured"
    end

    test "returns error for unsupported provider", %{conn: conn} do
      conn = get(conn, ~p"/auth/facebook")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Unsupported"
    end
  end

  describe "callback (GET /auth/:provider/callback)" do
    test "redirects to login with error for unconfigured provider", %{conn: conn} do
      conn = get(conn, ~p"/auth/github/callback", %{"code" => "test"})
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not configured"
    end

    test "returns error for unsupported provider", %{conn: conn} do
      conn = get(conn, ~p"/auth/facebook/callback", %{"code" => "test"})
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Unsupported"
    end
  end
end
