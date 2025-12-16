# edge_admin/lib/edge_admin_web/controllers/nodes/metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.MetricsController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.MetricsSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Nodes.Metrics"])

  operation(:index,
    summary: "Get node metrics",
    description: "Get current system metrics for a specific node",
    parameters: [
      node_id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Node metrics", "application/json", MetricsSchemas.MetricsResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.GenericErrorResponse}
    }
  )

  def index(conn, %{"node_id" => node_id}) do
    with {:ok, node} <- Nodes.get_node(node_id),
         {:ok, metrics} <- Nodes.list_node_metrics(node) do
      render(conn, :index, metrics: metrics, node_id: node_id)
    else
      {:error, :metrics_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Metrics service unavailable"})

      error ->
        error
    end
  end
end
