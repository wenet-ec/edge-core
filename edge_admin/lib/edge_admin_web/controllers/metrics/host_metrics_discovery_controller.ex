# edge_admin/lib/edge_admin_web/controllers/metrics/host_metrics_discovery_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.HostMetricsDiscoveryController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.Metrics.DiscoverySchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index]

  tags(["Internal.Metrics"])

  operation(:index,
    summary: "Host metrics service discovery",
    description:
      "Service discovery endpoint for Prometheus HTTP SD (host metrics). Returns all active nodes grouped by cluster in the format expected by http_sd_configs.",
    responses: %{
      200 => {"Service discovery targets", "application/json", DiscoverySchemas.DiscoveryResponse}
    }
  )

  def index(conn, _params) do
    metrics_base_url = Application.get_env(:edge_admin, :metrics_base_url)

    target_groups =
      [prefix: false, filter_status: ["healthy", "unhealthy"]]
      |> Nodes.list_cluster_node_mappings()
      |> Enum.map(fn %{name: cluster_name, nodes: node_ids} ->
        targets =
          Enum.map(node_ids, fn node_id ->
            "#{metrics_base_url}/api/v1/nodes/#{node_id}/metrics/host/raw"
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
