# edge_admin/lib/edge_admin_web/controllers/metrics/wireguard_metrics_discovery_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.WireguardMetricsDiscoveryController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Metrics.DiscoverySchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeQueryParams

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index]

  tags(["Internal.Metrics"])

  operation(:index,
    summary: "WireGuard metrics service discovery",
    description:
      "Service discovery endpoint for Prometheus HTTP SD (WireGuard metrics). Returns every node matching the list-node filters in the format expected by http_sd_configs. The response is a complete, unpaginated target snapshot; without status__in, it includes healthy, unhealthy, and unreachable nodes.",
    parameters: NodeQueryParams.filters(),
    responses: %{
      200 => {"Service discovery targets", "application/json", DiscoverySchemas.DiscoveryResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    metrics_base_url = Application.get_env(:edge_admin, :metrics_base_url)

    with {:ok, nodes} <- Nodes.list_nodes_for_discovery(params) do
      target_groups =
        Enum.map(nodes, fn node ->
          %{
            targets: [metrics_base_url],
            labels: %{
              cluster: node.cluster.name,
              job: "node-wireguard-metrics",
              __metrics_path__: "/api/v1/nodes/#{node.id}/metrics/wireguard/raw",
              node_id: node.id
            }
          }
        end)

      render(conn, :index, target_groups: target_groups)
    end
  end
end
