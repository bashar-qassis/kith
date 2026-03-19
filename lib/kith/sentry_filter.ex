defmodule Kith.SentryFilter do
  @moduledoc """
  Filters noisy exceptions from being reported to Sentry.
  Excludes 404, auth errors, and common non-actionable exceptions.
  """

  @behaviour Sentry.EventFilter

  @impl true
  def exclude_exception?(%Phoenix.Router.NoRouteError{}, _source), do: true
  def exclude_exception?(%Ecto.NoResultsError{}, _source), do: true
  def exclude_exception?(_, _), do: false
end
