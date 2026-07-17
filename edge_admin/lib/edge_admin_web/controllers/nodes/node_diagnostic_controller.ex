# edge_admin/lib/edge_admin_web/controllers/nodes/node_diagnostic_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeDiagnosticController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Diagnostics
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeDiagnosticSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:show]

  tags(["Nodes.Diagnostics"])

  operation(:show,
    summary: "Get node diagnostics",
    description: "Returns a read-only diagnostic report for a node.",
    parameters: [EdgeAdminWeb.Schemas.PathParams.uuid(:id, "Node ID")],
    responses: %{
      200 => {"Node diagnostics", "application/json", NodeDiagnosticSchemas.NodeDiagnosticResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"No diagnostic report available", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, diagnostic} <- Diagnostics.get_node_diagnostics(id) do
      render(conn, :show, conn: conn, diagnostic: diagnostic)
    end
  end
end
