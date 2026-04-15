# edge_admin/lib/edge_admin/prom_ex/prom_ex.ex
defmodule EdgeAdmin.PromEx do
  @moduledoc """
  PromEx configuration for EdgeAdmin application.
  """

  use PromEx, otp_app: :edge_admin

  alias PromEx.Plugins

  require Logger

  @impl true
  def plugins do
    Logger.info("PromEx: Loading plugins...")

    [
      # PromEx built in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, endpoint: EdgeAdminWeb.Endpoint, router: EdgeAdminWeb.Router},
      {Plugins.Ecto, otp_app: :edge_admin, repos: [EdgeAdmin.Repo]},
      {Plugins.Oban, otp_app: :edge_admin},
      EdgeAdmin.PromEx.EdgeAdminPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "edge_admin_prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      # PromEx built in Grafana dashboards
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"},
      {:edge_admin, "grafana_dashboards/edge_admin.json"},
      {:edge_admin, "grafana_dashboards/edge_agent.json"}
    ]
  end
end
