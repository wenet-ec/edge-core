# edge_admin/lib/edge_admin_web/controllers/nodes/node_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug DegradedMode, :block when action in [:change_cluster, :delete]
  plug DegradedMode, :allow when action in [:index, :show]

  tags(["Nodes.Node"])

  operation(:index,
    summary: "List all nodes",
    description: "Returns a paginated list of all registered edge nodes with filtering and sorting",
    parameters: [
      page: [
        in: :query,
        description: "Page number",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1, default: 1},
        example: 1
      ],
      page_size: [
        in: :query,
        description: "Items per page",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 100, default: 20},
        example: 20
      ],
      order_by: [
        in: :query,
        description: "Comma-separated list of fields to sort by",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at,status"
      ],
      order_directions: [
        in: :query,
        description: "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc,asc"
      ],
      id_type: [
        in: :query,
        description: "Filter by node ID type",
        schema: %OpenApiSpex.Schema{type: :string, enum: ["persistent", "random"]}
      ],
      status: [
        in: :query,
        description: "Filter by node status",
        schema: %OpenApiSpex.Schema{type: :string, enum: ["healthy", "unhealthy", "unreachable"]}
      ],
      version: [
        in: :query,
        description: "Filter by agent version (exact match or wildcard: 1.0.0, 1.*, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      self_update_enabled: [
        in: :query,
        description: "Filter by self-update enabled status",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      last_seen_at__gte: [
        in: :query,
        description:
          "Filter nodes last seen after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"}
      ],
      last_seen_at__lte: [
        in: :query,
        description:
          "Filter nodes last seen before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"}
      ],
      inserted_at__gte: [
        in: :query,
        description:
          "Filter nodes inserted after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"}
      ],
      inserted_at__lte: [
        in: :query,
        description:
          "Filter nodes inserted before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"}
      ],
      cluster_name: [
        in: :query,
        description: "Filter by cluster name (exact match or wildcard: prod*, *east, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ]
    ],
    responses: %{
      200 => {"Paginated list of nodes", "application/json", NodeSchemas.NodePaginatedResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {nodes, meta}} <- Nodes.list_nodes(params) do
      render(conn, :index, nodes: nodes, meta: meta)
    end
  end

  operation(:show,
    summary: "Get a specific node",
    description: "Returns details for a specific node by ID",
    parameters: [
      id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Node details", "application/json", NodeSchemas.NodeSingleResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    with {:ok, node} <- Nodes.get_node(id) do
      render(conn, :show, node: node)
    end
  end

  operation(:change_cluster,
    summary: "Change a node's cluster",
    description:
      "Move a node to a different cluster. Performs cluster migration via Netmaker (best-effort, reconciliation worker handles failures).\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [
      id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Cluster change parameters", "application/json", NodeSchemas.ChangeClusterRequest},
    responses: %{
      200 => {"Node cluster changed successfully", "application/json", NodeSchemas.NodeSingleResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      422 =>
        {"Validation error (incl. cluster name not found)", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def change_cluster(conn, %{"id" => id} = params) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, updated_node} <- Nodes.change_node_cluster(node, params) do
      render(conn, :show, node: updated_node)
    end
  end

  operation(:delete,
    summary: "Delete a node",
    description:
      "Delete a node from Netmaker and database in a transaction. Cascades to ssh_usernames, ssh_public_keys, and command_executions.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [
      id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      204 => {"Node deleted successfully", "", nil},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def delete(conn, %{"id" => id}) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, _node} <- Nodes.delete_node(node) do
      send_resp(conn, :no_content, "")
    end
  end
end
