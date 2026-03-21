defmodule KithWeb.PageControllerTest do
  use KithWeb.ConnCase

  test "GET / redirects unauthenticated users to login", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/users/log-in"
  end

  test "GET /terms renders Terms of Service page", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms of Service"
  end
end
