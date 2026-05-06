# edge_agent/lib/edge_agent/prom_ex/prom_ex.ex
defmodule EdgeAgent.PromEx do
  @moduledoc """
  PromEx configuration for EdgeAgent application.

  Wires up the upstream PromEx plugins (Application, Beam, Phoenix, Ecto, Oban)
  plus our custom `EdgeAgent.PromEx.EdgeAgentPlugin` that emits agent-specific
  business metrics. The corresponding agent Grafana dashboard
  (`edge_agent.json`) lives under `edge_admin/priv/grafana_dashboards/` so
  operators import it once at the admin tier; the agent itself does not serve
  custom dashboards.
  """

  use PromEx, otp_app: :edge_agent

  alias PromEx.Plugins

  @impl true
  def plugins do
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
    # Built-in PromEx dashboards. The agent-specific `edge_agent.json` is
    # operator-imported from `edge_admin/priv/grafana_dashboards/`; it is not
    # bundled here.
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
