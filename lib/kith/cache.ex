defmodule Kith.Cache do
  @moduledoc """
  Wrapper around Cachex for typed cache access.
  Primary use: geocoding result caching (24h TTL).
  """

  @cache :kith_cache

  def get(key), do: Cachex.get(@cache, key)
  def put(key, value, opts \\ []), do: Cachex.put(@cache, key, value, opts)
  def delete(key), do: Cachex.del(@cache, key)

  def fetch(key, fallback, opts \\ []) do
    Cachex.fetch(@cache, key, fn _key -> {:commit, fallback.()} end, opts)
  end
end
