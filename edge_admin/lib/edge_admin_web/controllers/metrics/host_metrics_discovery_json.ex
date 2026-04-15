# edge_admin/lib/edge_admin_web/controllers/metrics/host_metrics_discovery_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.HostMetricsDiscoveryJSON do
  @doc """
  Renders host metrics discovery targets for Prometheus HTTP SD.
  """
  def index(%{target_groups: target_groups}) do
    target_groups
  end
end
