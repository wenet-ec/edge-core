# edge_admin/lib/edge_admin_web/controllers/nodes/node_recovery_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeRecoveryKeyController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeSchemas
  alias EdgeAdminWeb.Schemas.PathParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug DegradedMode, :block

  tags(["Nodes.RecoveryKey"])

  operation(:create,
    summary: "Create a node recovery key",
    description: "Creates or replaces the node's one-use recovery key.",
    parameters: [PathParams.uuid(:id, "Node ID")],
    responses: %{
      201 => {"Recovery key created", "application/json", NodeSchemas.NodeRecoveryKeyResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create(conn, %{id: id}) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, recovery_key} <- Nodes.create_node_recovery_key(node) do
      conn
      |> put_status(:created)
      |> json(EdgeAdminWeb.ResponseEnvelope.success(conn, %{recovery_key: recovery_key}))
    end
  end

  operation(:delete,
    summary: "Delete a node recovery key",
    description: "Deletes the node's active recovery key.",
    parameters: [PathParams.uuid(:id, "Node ID")],
    responses: %{
      204 => {"Recovery key deleted", "", nil},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, _node} <- Nodes.delete_node_recovery_key(node) do
      send_resp(conn, :no_content, "")
    end
  end
end
