defmodule Kith.Immich.Client do
  @moduledoc """
  HTTP client for communicating with the Immich REST API.

  All calls use per-account credentials (base_url + api_key).
  Authentication is via `x-api-key` header (not Bearer token).
  Immich integration is strictly read-only — no PUT/POST/DELETE calls.
  """

  require Logger

  @timeout 30_000

  @doc """
  Lists all named people from the Immich instance.

  Returns `{:ok, [%{id: String.t(), name: String.t(), thumbnail_url: String.t()}]}`
  or `{:error, reason}`.
  """
  def list_people(base_url, api_key) do
    url = "#{String.trim_trailing(base_url, "/")}/api/people"

    result =
      Req.get(url,
        headers: [{"x-api-key", api_key}],
        receive_timeout: @timeout
      )

    case result do
      {:ok, %{status: 200, body: %{"people" => people}}} ->
        parsed =
          people
          |> Enum.filter(&(is_binary(&1["name"]) && &1["name"] != ""))
          |> Enum.map(fn person ->
            %{
              id: person["id"],
              name: person["name"],
              thumbnail_url:
                "#{String.trim_trailing(base_url, "/")}/api/people/#{person["id"]}/thumbnail"
            }
          end)

        {:ok, parsed}

      {:ok, %{status: 200, body: people}} when is_list(people) ->
        parsed =
          people
          |> Enum.filter(&(is_binary(&1["name"]) && &1["name"] != ""))
          |> Enum.map(fn person ->
            %{
              id: person["id"],
              name: person["name"],
              thumbnail_url:
                "#{String.trim_trailing(base_url, "/")}/api/people/#{person["id"]}/thumbnail"
            }
          end)

        {:ok, parsed}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, %{reason: :timeout}} ->
        {:error, :timeout}

      {:error, _reason} ->
        {:error, :network_error}
    end
  end

  @doc """
  Downloads a photo/thumbnail from Immich by asset URL.
  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  def download_asset(url, api_key) do
    case Req.get(url, headers: [{"x-api-key", api_key}], receive_timeout: @timeout) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, _} -> {:error, :network_error}
    end
  end
end
