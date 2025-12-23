# edge_admin/lib/edge_admin_web/controllers/nodes/alias_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.AliasController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.AliasSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Nodes.Alias"])

  operation(:index,
    summary: "List all aliases",
    description: "Returns a paginated list of node aliases with filtering and sorting",
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
        example: "inserted_at,name"
      ],
      order_directions: [
        in: :query,
        description:
          "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc,asc"
      ],
      name: [
        in: :query,
        description: "Filter by alias name (exact match or wildcard: prod*, *east, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      cluster_name: [
        in: :query,
        description: "Filter by cluster name (exact match or wildcard: prod*, *east, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      inserted_at__gte: [
        in: :query,
        description: "Filter aliases inserted after or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ],
      inserted_at__lte: [
        in: :query,
        description: "Filter aliases inserted before or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ]
    ],
    responses: %{
      200 => {"Paginated list of aliases", "application/json", AliasSchemas.AliasListResponse}
    }
  )

  def index(conn, params) do
    {:ok, {aliases, meta}} = Nodes.list_aliases(params)
    render(conn, :index, aliases: aliases, meta: meta)
  end

  operation(:show,
    summary: "Get a specific alias",
    description: "Returns details for a specific alias by ID",
    parameters: [
      id: [
        in: :path,
        description: "Alias ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Alias details", "application/json", AliasSchemas.AliasResponse},
      404 => {"Alias not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    with {:ok, alias_record} <- Nodes.get_alias(id) do
      render(conn, :show, alias: alias_record)
    end
  end

  operation(:create,
    summary: "Create a new alias for a node",
    description: "Creates a new alias and corresponding DNS entry for the specified node",
    parameters: [
      node_id: [
        in: :path,
        description: "Node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid},
        required: true
      ]
    ],
    request_body: {"Alias creation parameters", "application/json", AliasSchemas.CreateAliasRequest},
    responses: %{
      201 => {"Alias created successfully", "application/json", AliasSchemas.AliasResponse},
      400 => {"Invalid request", "application/json", CommonSchemas.ErrorResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def create(conn, %{"node_id" => node_id} = params) do
    with {:ok, node} <- Nodes.get_node(node_id),
         {:ok, alias_record} <- Nodes.create_alias(node, params) do
      conn
      |> put_status(:created)
      |> render(:show, alias: alias_record)
    end
  end

  operation(:delete,
    summary: "Delete an alias",
    description: "Deletes an alias and its corresponding DNS entry",
    parameters: [
      id: [
        in: :path,
        description: "Alias ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      204 => {"Alias deleted successfully", "application/json", nil},
      404 => {"Alias not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{"id" => id}) do
    with {:ok, alias_record} <- Nodes.get_alias(id),
         {:ok, _} <- Nodes.delete_alias(alias_record) do
      send_resp(conn, :no_content, "")
    end
  end
end
