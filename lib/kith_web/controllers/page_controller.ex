defmodule KithWeb.PageController do
  use KithWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
