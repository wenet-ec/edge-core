# edge_admin/lib/edge_admin_web/controllers/agents/node_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.Agents.NodeSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug DegradedMode, :block when action in [:create]
  plug DegradedMode, :allow when action in [:update_health_check]

  tags(["Internal.Agents"])

  operation(:create,
    summary: "Register a node",
    description: "Agent registers itself with admin, receives api_token and proxy_password.",
    responses: %{
      201 => {"Node registered", "application/json", NodeSchemas.NodeRegistrationResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create(conn, params) do
    with {:ok, node} <- Nodes.register_node(Map.merge(params, conn.body_params)) do
      conn
      |> put_status(:created)
      |> render(:show, node: node)
    end
  end

  operation(:update_health_check,
    summary: "Report node health check",
    description:
      "Agent reports its health status when using HTTP fallback mode. Node ID is inferred from the API token.",
    responses: %{
      200 => {"Health check recorded", "application/json", NodeSchemas.NodeHealthCheckResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def update_health_check(conn, params) do
    node = conn.assigns.current_node

    with {:ok, updated_node} <- Nodes.update_node_health_check(node, Map.merge(params, conn.body_params)) do
      render(conn, :show, node: updated_node)
    end
  end
end
