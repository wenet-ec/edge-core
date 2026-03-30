# edge_agent/lib/edge_agent/prom_ex.ex
defmodule EdgeAgent.PromEx do
  @moduledoc """
  PromEx configuration for EdgeAgent application.
  """

  use PromEx, otp_app: :edge_agent

  alias PromEx.Plugins

  require Logger

  @impl true
  def plugins do
    Logger.info("PromEx: Loading plugins...")

    [
      # PromEx built in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, endpoint: EdgeAgentWeb.Endpoint, router: EdgeAgentWeb.Router},
      {Plugins.Ecto, otp_app: :edge_agent, repos: [EdgeAgent.Repo]},
      {Plugins.Oban, otp_app: :edge_agent},
      EdgeAgent.PromEx.EdgeAgentPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "edge_agent_prometheus",
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
      {:prom_ex, "oban.json"}
      # Note: edge_agent.json will be stored in admin's priv/grafana_dashboards for reference
    ]
  end
end
