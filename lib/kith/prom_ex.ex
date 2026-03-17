defmodule Kith.PromEx do
  @moduledoc """
  Prometheus metrics via PromEx.
  Metrics endpoint at /metrics (admin-auth gated in Phase 12).
  """

  use PromEx, otp_app: :kith

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: KithWeb.Router},
      {PromEx.Plugins.Ecto, repos: [Kith.Repo]},
      PromEx.Plugins.Oban
    ]
  end

  @impl true
  def dashboard_assigns do
    [datasource_id: "prometheus"]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
