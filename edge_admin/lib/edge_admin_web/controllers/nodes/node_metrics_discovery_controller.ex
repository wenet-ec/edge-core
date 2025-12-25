# lib/edge_admin_web/controllers/nodes/node_metrics_discovery_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeMetricsDiscoveryController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Nodes

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  @doc """
  Service discovery endpoint for vmagent HTTP SD.
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
            "#{metrics_base_url}/api/nodes/#{node_id}/metrics/raw"
          end)

        %{
          targets: targets,
          labels: %{
            cluster: cluster_name,
            job: "edge-nodes"
          }
        }
      end)

    json(conn, target_groups)
  end

  @doc """
  Raw metrics proxy endpoint.
  Scrapes Prometheus metrics from a node via Gateway and returns raw text format.

  This endpoint is NOT documented in Swagger.
  """
  def show(conn, %{"node_id" => node_id}) do
    with {:ok, metrics_text} <- Nodes.scrape_node_metrics(node_id) do
      conn
      |> put_resp_content_type("text/plain; version=0.0.4")
      |> send_resp(200, metrics_text)
    end
  end
end
