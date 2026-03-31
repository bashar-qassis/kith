defmodule Kith.Application do
  @moduledoc false

  use Application
  import Cachex.Spec

  @impl true
  def start(_type, _args) do
    children = base_children() ++ mode_children()
    opts = [strategy: :one_for_one, name: Kith.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    # Install fuse circuit breakers before starting supervised children
    Kith.Geocoding.install_fuse()
    Kith.Weather.install_fuse()
    # Attach Sentry telemetry handler for Oban job failures
    Kith.SentryEventHandler.attach()
    # Capture crashes via Erlang logger handler (Sentry v10+, replaces PlugCapture)
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{})

    [
      Kith.Vault,
      Kith.Repo,
      {Finch, name: Swoosh.Finch, pools: %{:default => [size: 10]}},
      {Oban, Application.fetch_env!(:kith, Oban)},
      {Cachex, name: :kith_cache, expiration: expiration(default: :timer.hours(24))},
      {Task.Supervisor, name: Kith.TaskSupervisor}
    ]
  end

  defp mode_children do
    case System.get_env("KITH_MODE", "web") do
      "worker" ->
        []

      _web ->
        [
          Kith.PromEx,
          KithWeb.Telemetry,
          {DNSCluster, query: Application.get_env(:kith, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Kith.PubSub},
          KithWeb.Endpoint
        ]
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    KithWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
