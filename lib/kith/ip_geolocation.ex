defmodule Kith.IpGeolocation do
  @moduledoc """
  IP-to-location resolution using local MaxMind GeoLite2 database via Geolix.

  Used for session audit metadata (city/country on login events).
  Falls back to Cloudflare CF-IPCountry header when available.
  Returns `{:error, :geoip_not_configured}` when `GEOIP_DB_PATH` is unset.
  """

  require Logger

  @cache_ttl :timer.hours(1)

  @doc """
  Looks up geolocation data for an IP address.
  Returns `{:ok, %{city: String.t(), country: String.t(), region: String.t()}}` or `{:error, reason}`.
  """
  def lookup(ip_string) when is_binary(ip_string) do
    cache_key = {:geoip, ip_string}

    case Cachex.get(:kith_cache, cache_key) do
      {:ok, nil} ->
        result = do_lookup(ip_string)

        case result do
          {:ok, data} ->
            Cachex.put(:kith_cache, cache_key, data, ttl: @cache_ttl)
            {:ok, data}

          error ->
            error
        end

      {:ok, cached} ->
        {:ok, cached}
    end
  end

  @doc """
  Extracts country from Cloudflare CF-IPCountry header if present.
  Returns `{:ok, %{country: String.t()}}` or `{:error, :not_available}`.
  """
  def from_cloudflare_header(conn) do
    case Plug.Conn.get_req_header(conn, "cf-ipcountry") do
      [country] when country not in ["", "XX", "T1"] ->
        {:ok, %{country: country, city: nil, region: nil}}

      _ ->
        {:error, :not_available}
    end
  end

  @doc "Returns true if Geolix database is configured."
  def configured? do
    System.get_env("GEOIP_DB_PATH") != nil
  end

  # -- Private --

  defp do_lookup(ip_string) do
    unless configured?() do
      {:error, :geoip_not_configured}
    else
      case :inet.parse_address(String.to_charlist(ip_string)) do
        {:ok, ip_tuple} ->
          case Geolix.lookup(ip_tuple, where: :city) do
            %{city: city_data, country: country_data, subdivisions: subdivisions} ->
              {:ok,
               %{
                 city: get_in(city_data || %{}, [:name]) || get_geolix_name(city_data),
                 country: get_in(country_data || %{}, [:iso_code]) || get_geolix_name(country_data),
                 region: get_geolix_name(List.first(subdivisions || []))
               }}

            %{country: country_data} ->
              {:ok,
               %{
                 city: nil,
                 country: get_in(country_data || %{}, [:iso_code]) || get_geolix_name(country_data),
                 region: nil
               }}

            nil ->
              {:error, :not_found}

            _ ->
              {:error, :not_found}
          end

        {:error, _} ->
          {:error, :invalid_ip}
      end
    end
  end

  defp get_geolix_name(nil), do: nil

  defp get_geolix_name(%{names: names}) when is_map(names) do
    Map.get(names, "en") || Map.get(names, :en)
  end

  defp get_geolix_name(_), do: nil
end
