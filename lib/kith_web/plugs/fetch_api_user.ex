defmodule KithWeb.Plugs.FetchApiUser do
  @moduledoc """
  Plug that extracts a Bearer token from the Authorization header,
  validates it against the `user_tokens` table, and loads the user + account.

  Returns 401 with RFC 7807 error if the token is missing, invalid,
  or the user/account is inactive.
  """

  import Plug.Conn
  alias Kith.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, raw_token} <- extract_bearer_token(conn),
         {user, _token_record} <- Accounts.get_user_by_api_token(raw_token) do
      scope = Kith.Accounts.Scope.for_user(user)

      conn
      |> assign(:current_scope, scope)
      |> assign(:current_api_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/problem+json")
        |> send_resp(
          401,
          Jason.encode!(%{
            type: "about:blank",
            title: "Unauthorized",
            status: 401,
            detail: "Missing or invalid API token."
          })
        )
        |> halt()
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> :error
    end
  end
end
