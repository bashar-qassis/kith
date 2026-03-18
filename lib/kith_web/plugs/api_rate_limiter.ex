defmodule KithWeb.Plugs.ApiRateLimiter do
  @moduledoc """
  Per-account rate limiting for API requests.

  1000 requests per hour per account. Adds rate limit headers to all responses.
  Must be placed AFTER `FetchApiUser` in the pipeline.
  """

  import Plug.Conn

  @default_limit 1000
  @default_period 3_600_000

  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      period: Keyword.get(opts, :period, @default_period)
    }
  end

  def call(conn, %{limit: limit, period: period}) do
    case conn.assigns[:current_scope] do
      %{user: %{account_id: account_id}} when not is_nil(account_id) ->
        key = "api_rate:account:#{account_id}"

        case Hammer.check_rate(key, period, limit) do
          {:allow, count} ->
            remaining = max(limit - count, 0)
            reset_at = System.system_time(:second) + div(period, 1000)

            conn
            |> put_resp_header("x-ratelimit-limit", to_string(limit))
            |> put_resp_header("x-ratelimit-remaining", to_string(remaining))
            |> put_resp_header("x-ratelimit-reset", to_string(reset_at))

          {:deny, _limit} ->
            retry_after = div(period, 1000)

            conn
            |> put_resp_content_type("application/problem+json")
            |> put_resp_header("retry-after", to_string(retry_after))
            |> put_resp_header("x-ratelimit-limit", to_string(limit))
            |> put_resp_header("x-ratelimit-remaining", "0")
            |> put_resp_header(
              "x-ratelimit-reset",
              to_string(System.system_time(:second) + retry_after)
            )
            |> send_resp(
              429,
              Jason.encode!(%{
                type: "about:blank",
                title: "Too Many Requests",
                status: 429,
                detail: "Account API rate limit exceeded. Try again in #{retry_after} seconds."
              })
            )
            |> halt()
        end

      _ ->
        # No account context (shouldn't happen if FetchApiUser ran), pass through
        conn
    end
  end
end
