# edge_admin/lib/edge_admin_web/controllers/metrics/wireguard_metrics_discovery_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.WireguardMetricsDiscoveryJSON do
  def index(%{target_groups: target_groups}) do
    target_groups
  end
end
