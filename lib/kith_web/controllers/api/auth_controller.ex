defmodule KithWeb.API.AuthController do
  @moduledoc """
  API authentication endpoints for bearer token management.

  POST /api/auth/token   — generate a new API token (email + password + optional TOTP)
  DELETE /api/auth/token  — revoke the current token
  DELETE /api/auth/token/:id — revoke a specific token by DB id
  """

  use KithWeb, :controller

  alias Kith.Accounts

  def create(conn, %{"email" => email, "password" => password} = params) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_status(401)
        |> put_resp_content_type("application/problem+json")
        |> json(%{
          type: "about:blank",
          title: "Unauthorized",
          status: 401,
          detail: "Invalid email or password."
        })

      user ->
        if user.totp_enabled do
          totp_code = params["totp_code"]

          cond do
            is_nil(totp_code) or totp_code == "" ->
              conn
              |> put_status(401)
              |> put_resp_content_type("application/problem+json")
              |> json(%{
                type: "about:blank",
                title: "Unauthorized",
                status: 401,
                detail: "TOTP code required."
              })

            Accounts.valid_totp_code?(user.totp_secret, totp_code) ->
              issue_token(conn, user)

            Accounts.use_recovery_code(user, totp_code) ->
              issue_token(conn, user)

            true ->
              conn
              |> put_status(401)
              |> put_resp_content_type("application/problem+json")
              |> json(%{
                type: "about:blank",
                title: "Unauthorized",
                status: 401,
                detail: "Invalid TOTP code."
              })
          end
        else
          issue_token(conn, user)
        end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> put_resp_content_type("application/problem+json")
    |> json(%{
      type: "about:blank",
      title: "Bad Request",
      status: 400,
      detail: "Missing email and password."
    })
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_api_user

    case Accounts.revoke_api_token(user, id) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{
          type: "about:blank",
          title: "Not Found",
          status: 404,
          detail: "Token not found."
        })
    end
  end

  def delete_current(conn, _params) do
    raw_token =
      case Plug.Conn.get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> String.trim(token)
        _ -> nil
      end

    if raw_token do
      Accounts.revoke_api_token_by_value(raw_token)
    end

    send_resp(conn, 204, "")
  end

  defp issue_token(conn, user) do
    {raw_token, _token_record} = Accounts.generate_api_token(user)

    conn
    |> put_status(201)
    |> json(%{token: raw_token, expires_at: nil})
  end
end
