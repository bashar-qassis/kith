defmodule Kith.SentryEventHandler do
  @moduledoc """
  Telemetry handler for capturing Oban job failures in Sentry.

  Only reports to Sentry on the final attempt (max_attempts reached)
  to avoid spamming Sentry on each retry.
  """

  require Logger

  @scrub_keys ~w(password password_confirmation token api_key secret current_password new_password)

  @doc "Attaches telemetry handlers for Oban + Sentry integration."
  def attach do
    :telemetry.attach(
      "kith-oban-sentry",
      [:oban, :job, :exception],
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  @doc false
  def handle_event([:oban, :job, :exception], _measurements, metadata, _config) do
    %{job: job, reason: reason, stacktrace: stacktrace} = metadata

    # Only report on final attempt
    if job.attempt >= job.max_attempts do
      Sentry.capture_exception(reason,
        stacktrace: stacktrace,
        extra: %{
          worker: job.worker,
          queue: job.queue,
          attempt: job.attempt,
          max_attempts: job.max_attempts,
          args: scrub_params(job.args)
        }
      )
    end
  end

  @doc """
  Scrubs sensitive keys from params before sending to Sentry.
  Used as a `before_send` callback.
  """
  def before_send(event) do
    update_in(event.request.data, fn data ->
      scrub_params(data)
    end)
  rescue
    _ -> event
  end

  @doc "Recursively scrubs sensitive keys from a map."
  def scrub_params(params) when is_map(params) do
    Map.new(params, fn
      {key, value} when is_binary(key) and key in @scrub_keys ->
        {key, "[FILTERED]"}

      {key, value} when is_atom(key) ->
        if Atom.to_string(key) in @scrub_keys do
          {key, "[FILTERED]"}
        else
          {key, scrub_params(value)}
        end

      {key, value} when is_map(value) ->
        {key, scrub_params(value)}

      {key, value} ->
        {key, value}
    end)
  end

  def scrub_params(other), do: other
end
