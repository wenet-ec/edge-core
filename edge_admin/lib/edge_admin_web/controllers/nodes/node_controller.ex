# edge_admin/lib/edge_admin_web/controllers/nodes/node_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeQueryParams
  alias EdgeAdminWeb.Schemas.Nodes.NodeSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug DegradedMode, :block when action in [:change_cluster, :delete]
  plug DegradedMode, :allow when action in [:index, :show]

  tags(["Nodes.Node"])

  operation(:index,
    summary: "List all nodes",
    description: "Returns a paginated list of all registered edge nodes with filtering and sorting",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort(example: "-inserted_at,status") ++
        NodeQueryParams.filters(),
    responses: %{
      200 => {"Paginated list of nodes", "application/json", NodeSchemas.NodePaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {nodes, meta}} <- Nodes.list_nodes(params) do
      render(conn, :index, conn: conn, nodes: nodes, meta: meta)
    end
  end

  operation(:show,
    summary: "Get a specific node",
    description: "Returns details for a specific node by ID",
    parameters: [PathParams.uuid(:id, "Node ID")],
    responses: %{
      200 => {"Node details", "application/json", NodeSchemas.NodeSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, node} <- Nodes.get_node(id) do
      render(conn, :show, conn: conn, node: node)
    end
  end

  operation(:change_cluster,
    summary: "Change a node's cluster",
    description:
      "Move a node to a different cluster. This clears the node's existing recovery key and removes its cluster-specific aliases; create a new recovery key explicitly if needed. The returned node reflects the saved cluster assignment immediately; network connectivity may briefly reflect the previous assignment while it converges.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [PathParams.uuid(:id, "Node ID")],
    request_body: {"Cluster change parameters", "application/json", NodeSchemas.ChangeClusterRequest, required: true},
    responses: %{
      200 => {"Node cluster changed successfully", "application/json", NodeSchemas.NodeSingleResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      409 =>
        {"Node already in the target cluster, or target cluster has reached its node limit", "application/json",
         CommonSchemas.ConflictResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def change_cluster(conn, %{id: id} = params) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, updated_node} <- Nodes.change_node_cluster(node, Map.merge(params, conn.body_params)) do
      render(conn, :show, conn: conn, node: updated_node)
    end
  end

  operation(:delete,
    summary: "Delete a node",
    description:
      "Delete a node and its associated Edge Core records. Command-execution history is retained.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [PathParams.uuid(:id, "Node ID")],
    responses: %{
      204 => {"Node deleted successfully", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, _node} <- Nodes.delete_node(node) do
      send_resp(conn, :no_content, "")
    end
  end
end
