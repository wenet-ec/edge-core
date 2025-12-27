# lib/edge_admin_web/controllers/metrics/host_metrics_discovery_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.HostMetricsDiscoveryController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Nodes

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index]

  @doc """
  Service discovery endpoint for vmagent HTTP SD (host metrics).
  Returns all active nodes grouped by cluster in the format expected by vmagent http_sd_configs.

  This endpoint is NOT documented in Swagger.
  """
  def index(conn, _params) do
    metrics_base_url = Application.get_env(:edge_admin, :metrics_base_url)

    target_groups =
      Nodes.list_cluster_node_mappings(prefix: false, filter_status: ["healthy", "unhealthy"])
      |> Enum.map(fn %{name: cluster_name, nodes: node_ids} ->
        targets =
          Enum.map(node_ids, fn node_id ->
            "#{metrics_base_url}/api/nodes/#{node_id}/metrics/host/raw"
          end)

        %{
          targets: targets,
          labels: %{
            cluster: cluster_name,
            job: "node-host-metrics"
          }
        }
      end)

    render(conn, :index, target_groups: target_groups)
  end
end
