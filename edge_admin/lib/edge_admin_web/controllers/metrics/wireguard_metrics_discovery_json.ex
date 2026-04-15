# edge_admin/lib/edge_admin_web/controllers/metrics/wireguard_metrics_discovery_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.WireguardMetricsDiscoveryJSON do
  @doc """
  Renders WireGuard metrics discovery targets for Prometheus HTTP SD.
  """
  def index(%{target_groups: target_groups}) do
    target_groups
  end
end
