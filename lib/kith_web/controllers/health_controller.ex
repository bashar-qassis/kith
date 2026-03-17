defmodule KithWeb.HealthController do
  use KithWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
