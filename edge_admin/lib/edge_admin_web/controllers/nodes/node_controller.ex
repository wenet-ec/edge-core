# edge_admin/lib/edge_admin_web/controllers/nodes/node_controller.ex
defmodule EdgeAdminWeb.Nodes.NodeController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Node
  alias EdgeAdminWeb.Schemas.Nodes.NodeSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback EdgeAdminWeb.FallbackController

  tags ["Nodes"]

  operation :index,
    summary: "List all nodes",
    description: "Returns a list of all registered edge nodes",
    responses: %{
      200 => {"List of nodes", "application/json", NodeSchemas.NodeListResponse}
    }

  def index(conn, _params) do
    nodes = Nodes.list_nodes()
    render(conn, :index, nodes: nodes)
  end

  operation :create,
    summary: "Create a new node",
    description: "Register a new edge node in the system",
    request_body: {"Node creation parameters", "application/json", NodeSchemas.NodeCreateRequest},
    responses: %{
      201 => {"Node created successfully", "application/json", NodeSchemas.NodeSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }

  def create(conn, %{"node" => node_params}) do
    with {:ok, %Node{} = node} <- Nodes.create_node_with_vpn_info(node_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/nodes/#{node}")
      |> render(:show, node: node)
    end
  end

  operation :show,
    summary: "Get a specific node",
    description: "Returns details for a specific node by ID",
    parameters: [
      id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid},
        example: "01234567-89ab-cdef-0123-456789abcdef"
      ]
    ],
    responses: %{
      200 => {"Node details", "application/json", NodeSchemas.NodeSingleResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse}
    }

  def show(conn, %{"id" => id}) do
    node = Nodes.get_node_with_vpn_info!(id)
    render(conn, :show, node: node)
  end

  operation :update,
    summary: "Update a node",
    description: "Update an existing node's information",
    parameters: [
      id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid},
        example: "01234567-89ab-cdef-0123-456789abcdef"
      ]
    ],
    request_body: {"Node update parameters", "application/json", NodeSchemas.NodeUpdateRequest},
    responses: %{
      200 => {"Node updated successfully", "application/json", NodeSchemas.NodeSingleResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }

  def update(conn, %{"id" => id, "node" => node_params}) do
    node = Nodes.get_node!(id)

    with {:ok, %Node{} = node} <- Nodes.update_node(node, node_params) do
      render(conn, :show, node: node)
    end
  end

  operation :delete,
    summary: "Delete a node",
    description: "Remove a node from the system",
    parameters: [
      id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid},
        example: "01234567-89ab-cdef-0123-456789abcdef"
      ]
    ],
    responses: %{
      204 => {"Node deleted successfully", "application/json", nil},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse}
    }

  def delete(conn, %{"id" => id}) do
    node = Nodes.get_node!(id)

    with {:ok, %Node{}} <- Nodes.delete_node(node) do
      send_resp(conn, :no_content, "")
    end
  end
end
