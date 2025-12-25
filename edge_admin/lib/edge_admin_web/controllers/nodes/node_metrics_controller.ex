# edge_admin/lib/edge_admin_web/controllers/nodes/node_metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeMetricsController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeMetricsSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Nodes.Metrics"])

  operation(:index,
    summary: "Get node metrics",
    description: """
    Get current system metrics for a specific node.

    **Modes:**
    - **Self-sufficient mode** (no METRICS_STORAGE_URL configured): Parses raw Prometheus metrics from node_exporter. Some fields like `cpu.usage_percent` and `network.*_per_sec` will be null.
    - **Enhanced mode** (METRICS_STORAGE_URL configured): Queries metrics storage with PromQL for complete metrics including rates and averages.
    """,
    parameters: [
      node_id: [
        in: :path,
        description: "Node UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Node metrics retrieved successfully", "application/json", NodeMetricsSchemas.MetricsResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.GenericErrorResponse}
    }
  )

  def index(conn, %{"node_id" => node_id}) do
    with {:ok, metrics} <- Nodes.list_node_metrics(node_id) do
      json(conn, metrics)
    end
  end
end
