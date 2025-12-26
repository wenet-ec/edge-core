# lib/edge_admin_web/controllers/metrics/host_metrics_discovery_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.HostMetricsDiscoveryJSON do
  @doc """
  Renders the host metrics discovery response in the format expected by vmagent.

  Returns an array of target groups. Each group contains:
  - targets: List of "ip:port" strings pointing to host metrics endpoints
  - labels: Metadata labels for the target group

  If no targets are available, returns an empty array.
  """
  def index(%{targets: targets}) do
    case targets do
      [] ->
        # Return empty array if no targets available
        []

      target_list ->
        # Return single target group with all nodes
        [
          %{
            targets: target_list,
            labels: %{
              job: "edge-nodes-host",
              scrape_source: "edge_admin_discovery"
            }
          }
        ]
    end
  end
end
