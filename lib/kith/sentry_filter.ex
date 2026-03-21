defmodule Kith.SentryFilter do
  @moduledoc """
  Filters noisy exceptions from being reported to Sentry.

  Excludes common non-actionable exceptions:
  - 404 (NoRouteError, NoResultsError)
  - 401/403 (authentication/authorization failures)
  """

  @behaviour Sentry.EventFilter

  @impl true
  # 404 — route not found
  def exclude_exception?(%Phoenix.Router.NoRouteError{}, _source), do: true
  # 404 — record not found via Repo.get!
  def exclude_exception?(%Ecto.NoResultsError{}, _source), do: true

  # 401/403 — Plug.Conn exceptions for auth failures
  def exclude_exception?(%Plug.Conn.WrapperError{conn: %{status: status}}, _source)
      when status in [401, 403, 404],
      do: true

  def exclude_exception?(_, _), do: false
end
