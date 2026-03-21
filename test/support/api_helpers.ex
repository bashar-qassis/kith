defmodule KithWeb.APIHelpers do
  @moduledoc """
  Convenience functions for API testing.

  Provides authenticated request helpers and RFC 7807 assertion macros.
  Imported automatically in `KithWeb.ConnCase`.

  ## Usage

      {conn, user, account} = create_api_token()
      conn |> api_get("/api/contacts") |> assert_rfc7807(200) # will fail — 200 is success
      conn |> api_post("/api/contacts", %{first_name: "Jane"})
  """

  import Plug.Conn
  import Phoenix.ConnTest, only: [json_response: 2]

  alias Kith.Accounts

  @endpoint KithWeb.Endpoint

  @doc """
  Creates a test account + user + API Bearer token.

  Returns `{conn_with_token, user, account}`.

  ## Options

    * `:role` - user role, default "admin"
    * `:conn` - base conn to use, default `Phoenix.ConnTest.build_conn()`

  ## Examples

      {conn, user, account} = create_api_token()
      {conn, viewer, _account} = create_api_token(role: "viewer")
  """
  def create_api_token(opts \\ []) do
    role = Keyword.get(opts, :role, "admin")
    base_conn = Keyword.get(opts, :conn) || Phoenix.ConnTest.build_conn()

    # Create user through the actual auth pipeline
    user = Kith.AccountsFixtures.user_fixture()

    user =
      if role != "admin" do
        {:ok, user} = Accounts.update_user_role(user, %{role: role})
        user
      else
        user
      end

    # Generate API token through the actual auth flow
    {raw_token, _token_record} = Accounts.generate_api_token(user)

    conn =
      base_conn
      |> put_req_header("authorization", "Bearer #{raw_token}")
      |> put_req_header("content-type", "application/json")

    {conn, user, user.account}
  end

  @doc """
  Sends an authenticated GET request and parses the JSON response.

  Returns the decoded response body.
  """
  def api_get(conn, path, params \\ %{}) do
    query = URI.encode_query(params)
    full_path = if query == "", do: path, else: "#{path}?#{query}"

    conn
    |> Phoenix.ConnTest.get(full_path)
  end

  @doc """
  Sends an authenticated POST request with JSON body and parses the response.
  """
  def api_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.post(path, Jason.encode!(body))
  end

  @doc """
  Sends an authenticated PATCH request with JSON body and parses the response.
  """
  def api_patch(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.patch(path, Jason.encode!(body))
  end

  @doc """
  Sends an authenticated DELETE request and returns the conn.
  """
  def api_delete(conn, path) do
    Phoenix.ConnTest.delete(conn, path)
  end

  @doc """
  Asserts a response matches RFC 7807 Problem Details format.

  Verifies the response has the given HTTP status code and contains
  the required `type`, `title`, and `status` fields.

  Returns the decoded response body for further assertions.

  ## Examples

      conn
      |> api_get("/api/contacts/99999")
      |> assert_rfc7807(404)

      body =
        conn
        |> api_post("/api/contacts", %{})
        |> assert_rfc7807(400)

      assert body["detail"] =~ "required"
  """
  def assert_rfc7807(conn, expected_status) do
    body = json_response(conn, expected_status)

    unless is_map(body) and Map.has_key?(body, "type") and
             Map.has_key?(body, "title") and Map.has_key?(body, "status") do
      raise ExUnit.AssertionError,
        message: """
        Expected RFC 7807 Problem Details response with keys: type, title, status

        Got: #{inspect(body)}
        """
    end

    unless body["status"] == expected_status do
      raise ExUnit.AssertionError,
        message: """
        RFC 7807 status field mismatch.
        Expected: #{expected_status}
        Got: #{body["status"]}
        """
    end

    body
  end
end
