defmodule KithWeb.API.DeviceController do
  @moduledoc """
  Stub endpoint for mobile push notification device registration.
  Returns 501 Not Implemented — to be implemented in v2.
  """

  use KithWeb, :controller

  alias KithWeb.API.ErrorJSON

  def create(conn, _params) do
    conn
    |> put_status(501)
    |> put_resp_content_type("application/problem+json")
    |> json(
      ErrorJSON.render(
        501,
        "Push notification device registration is not yet supported.",
        conn.request_path
      )
    )
  end
end
