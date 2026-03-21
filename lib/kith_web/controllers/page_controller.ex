defmodule KithWeb.PageController do
  use KithWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_scope] do
      redirect(conn, to: ~p"/dashboard")
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end

  def tos(conn, _params) do
    render(conn, :tos, layout: {KithWeb.Layouts, :root})
  end
end
