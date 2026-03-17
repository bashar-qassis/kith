defmodule Kith.RateLimiter do
  @moduledoc """
  Rate limiting wrapper around Hammer with named rules.
  """

  @login_limit {10, 60_000}
  @signup_limit {5, 60_000}
  @api_limit {1000, 3_600_000}

  def check_login(ip) do
    {limit, period} = @login_limit
    check("login:#{format_ip(ip)}", limit, period)
  end

  def check_signup(ip) do
    {limit, period} = @signup_limit
    check("signup:#{format_ip(ip)}", limit, period)
  end

  def check_api(account_id) do
    {limit, period} = @api_limit
    check("api:#{account_id}", limit, period)
  end

  defp check(key, limit, period) do
    case Hammer.check_rate(key, period, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after} -> {:error, :rate_limited, retry_after}
    end
  end

  defp format_ip(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()
  defp format_ip(ip) when is_binary(ip), do: ip
end
