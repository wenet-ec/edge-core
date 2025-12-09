# edge_admin/lib/edge_admin_web/controllers/nodes/node_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Nodes.Node"])

  operation(:index,
    summary: "List all nodes",
    description:
      "Returns a paginated list of all registered edge nodes with filtering and sorting",
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
      sort: [
        in: :query,
        description: "Sort specification: field1:dir1,field2:dir2",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at:desc"
      ],
      status: [
        in: :query,
        description: "Filter by node status",
        schema: %OpenApiSpex.Schema{type: :string, enum: ["online", "offline"]}
      ],
      id_type: [
        in: :query,
        description: "Filter by node ID type",
        schema: %OpenApiSpex.Schema{
          type: :string,
          enum: ["machine_id", "hardware_id", "temporary_id"]
        }
      ]
    ],
    responses: %{
      200 => {"Paginated list of nodes", "application/json", NodeSchemas.NodePaginatedResponse}
    }
  )

  def index(conn, params) do
    page_result = Nodes.list_nodes_with_filtering_pagination(params)
    render(conn, :index, page_result: page_result)
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
    node = Nodes.get_node!(id)
    render(conn, :show, node: node)
  end

  operation(:change_cluster,
    summary: "Change a node's cluster",
    description:
      "Move a node to a different cluster. Performs cluster migration via Netmaker (best-effort, reconciliation worker handles failures).",
    parameters: [
      id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    request_body:
      {"Cluster change parameters", "application/json", NodeSchemas.ChangeClusterRequest},
    responses: %{
      200 => {"Node cluster changed successfully", "application/json", NodeSchemas.NodeSingleResponse},
      404 => {"Node or cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def change_cluster(conn, %{"id" => id, "node" => %{"cluster_name" => cluster_name}}) do
    node = Nodes.get_node!(id)

    {:ok, updated_node} = Nodes.change_node_cluster(node, cluster_name)
    render(conn, :show, node: updated_node)
  end

  operation(:delete,
    summary: "Delete a node",
    description:
      "Delete a node from Netmaker and database in a transaction. Cascades to ssh_usernames, ssh_public_keys, and command_executions.",
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
      422 =>
        {"Failed to delete node from Netmaker", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def delete(conn, %{"id" => id}) do
    node = Nodes.get_node!(id)

    case Nodes.delete_node(node) do
      {:ok, _node} ->
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete node: #{inspect(reason)}"})
    end
  end
end
