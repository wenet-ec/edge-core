# edge_admin/lib/edge_admin_web/controllers/nodes/node_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  @status_enum Node.status_strings()
  @id_type_enum Node.id_type_strings()

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug DegradedMode, :block when action in [:change_cluster, :delete]
  plug DegradedMode, :allow when action in [:index, :show]

  tags(["Nodes.Node"])

  operation(:index,
    summary: "List all nodes",
    description: "Returns a paginated list of all registered edge nodes with filtering and sorting",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort(order_by_example: "inserted_at,status", order_directions_example: "desc,asc") ++
        [
          QueryParams.uuid_in_filter(:node_id,
            description: "Filter by node IDs — comma-separated list of UUIDs (e.g. node_id__in=uuid1,uuid2)"
          ),
          QueryParams.enum_in_filter(:id_type, @id_type_enum,
            description: "Filter by node ID type (e.g. id_type__in=persistent,random)"
          ),
          QueryParams.enum_in_filter(:status, @status_enum,
            description: "Filter by node status (e.g. status__in=healthy,unhealthy)"
          ),
          QueryParams.string_filter(:version,
            description: "Filter by agent version (exact match or wildcard: 1.0.0, 1.*, etc.)"
          ),
          QueryParams.boolean_filter(:self_update_enabled, description: "Filter by self-update enabled status"),
          QueryParams.string_filter(:cluster_name,
            description: "Filter by cluster name — exact match or wildcard (prod*, *east, *rod*)"
          ),
          QueryParams.string_in_filter(:cluster_name,
            description:
              "Filter by cluster name — comma-separated list for IN match (e.g. cluster_name__in=prod,staging)"
          )
        ] ++
        QueryParams.datetime_range_filter(:last_seen_at) ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
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
      "Move a node to a different cluster. Performs cluster migration via Netmaker (best-effort, reconciliation worker handles failures).\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
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
      "Delete a node. Removes the Netmaker host first, then the DB row. Cascade: `ssh_usernames` (and their `ssh_public_keys`) and `aliases` are deleted; `command_executions` are kept with `node_id` set to NULL for history.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
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
