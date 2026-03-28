defmodule Kith.DAV.Auth do
  @moduledoc """
  HTTP Basic Auth for DAV clients.

  Validates credentials against Kith user accounts. DAV clients (Apple Contacts,
  DAVx5, Thunderbird) send HTTP Basic Auth on every request over TLS.
  """

  import Plug.Conn
  alias Kith.Accounts

  @doc """
  Authenticates the connection using HTTP Basic Auth.

  Returns `{:ok, user}` on success or `{:error, :unauthorized}` on failure.
  """
  def authenticate(conn) do
    with ["Basic " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [email, password] <- String.split(decoded, ":", parts: 2),
         %Kith.Accounts.User{confirmed_at: confirmed_at} = user
         when not is_nil(confirmed_at) <-
           Accounts.get_user_by_email_and_password(email, password) do
      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end

  @doc """
  Plug-compatible function that requires Basic Auth on the connection.

  On success, assigns `:current_scope` with the authenticated user and account.
  On failure, sends a 401 response with a WWW-Authenticate challenge and halts.
  """
  def require_auth(conn) do
    case authenticate(conn) do
      {:ok, user} ->
        scope = Accounts.Scope.for_user(user)
        assign(conn, :current_scope, scope)

      {:error, _} ->
        conn
        |> put_resp_header("www-authenticate", ~s(Basic realm="Kith CardDAV"))
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end
end
