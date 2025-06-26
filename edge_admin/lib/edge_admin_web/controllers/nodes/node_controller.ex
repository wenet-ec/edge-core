# edge_admin/lib/edge_admin_web/controllers/nodes/node_controller.ex
defmodule EdgeAdminWeb.Nodes.NodeController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Node
  alias EdgeAdminWeb.Schemas.Nodes.NodeSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.FallbackController)

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
      ],
      vpn_ip: [
        in: :query,
        description: "Filter by VPN IP (supports wildcards with *)",
        schema: %OpenApiSpex.Schema{type: :string}
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

  operation(:create,
    summary: "Create a new node",
    description: "Register a new edge node in the system",
    request_body: {"Node creation parameters", "application/json", NodeSchemas.NodeCreateRequest},
    responses: %{
      201 => {"Node created successfully", "application/json", NodeSchemas.NodeSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def create(conn, %{"node" => node_params}) do
    with {:ok, %Node{} = node} <- Nodes.create_node_with_vpn_info(node_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/nodes/#{node}")
      |> render(:show, node: node)
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
    node = Nodes.get_node_with_vpn_info!(id)
    render(conn, :show, node: node)
  end

  operation(:update,
    summary: "Update a node",
    description: "Update an existing node's information",
    parameters: [
      id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Node update parameters", "application/json", NodeSchemas.NodeUpdateRequest},
    responses: %{
      200 => {"Node updated successfully", "application/json", NodeSchemas.NodeSingleResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def update(conn, %{"id" => id, "node" => node_params}) do
    node = Nodes.get_node!(id)

    with {:ok, %Node{} = node} <- Nodes.update_node(node, node_params) do
      render(conn, :show, node: node)
    end
  end
end
