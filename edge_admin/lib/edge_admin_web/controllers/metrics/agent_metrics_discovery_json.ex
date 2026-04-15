# edge_admin/lib/edge_admin_web/controllers/metrics/agent_metrics_discovery_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.AgentMetricsDiscoveryJSON do
  @doc """
  Renders agent metrics discovery targets for Prometheus HTTP SD.
  """
  def index(%{target_groups: target_groups}) do
    target_groups
  end
end
