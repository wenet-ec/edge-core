# edge_admin/lib/edge_admin_web/controllers/nodes/alias_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.AliasController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.AliasSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

  tags(["Nodes.Alias"])

  operation(:index,
    summary: "List all aliases",
    description: "Returns a paginated list of node aliases with filtering and sorting",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort(order_by_example: "inserted_at,name", order_directions_example: "desc,asc") ++
        [
          QueryParams.string_filter(:name,
            description: "Filter by alias name (exact match or wildcard: prod*, *east, etc.)"
          ),
          QueryParams.uuid_filter(:node_id, description: "Filter by node ID (exact match UUID)"),
          QueryParams.string_filter(:cluster_name,
            description: "Filter by cluster name (exact match or wildcard: prod*, *east, etc.)"
          )
        ] ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
    responses: %{
      200 => {"Paginated list of aliases", "application/json", AliasSchemas.AliasPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {aliases, meta}} <- Nodes.list_aliases(params) do
      render(conn, :index, conn: conn, aliases: aliases, meta: meta)
    end
  end

  operation(:show,
    summary: "Get a specific alias",
    description: "Returns details for a specific alias by ID",
    parameters: [PathParams.uuid(:id, "Alias ID")],
    responses: %{
      200 => {"Alias details", "application/json", AliasSchemas.AliasSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Alias not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, alias_record} <- Nodes.get_alias(id) do
      render(conn, :show, conn: conn, alias: alias_record)
    end
  end

  operation(:create,
    summary: "Create a new alias for a node",
    description: "Creates a new alias and corresponding DNS entry for the specified node",
    parameters: [PathParams.uuid(:node_id, "Node ID")],
    request_body: {"Alias creation parameters", "application/json", AliasSchemas.CreateAliasRequest, required: true},
    responses: %{
      201 => {"Alias created successfully", "application/json", AliasSchemas.AliasSingleResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      409 =>
        {"Alias name already exists in this cluster, or node is not yet enrolled/has no IP in the VPN network",
         "application/json", CommonSchemas.ConflictResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create(conn, %{node_id: node_id} = params) do
    with {:ok, node} <- Nodes.get_node(node_id),
         {:ok, alias_record} <- Nodes.create_alias(node, Map.merge(params, conn.body_params)) do
      conn
      |> put_status(:created)
      |> render(:show, conn: conn, alias: alias_record)
    end
  end

  operation(:delete,
    summary: "Delete an alias",
    description: "Deletes an alias and its corresponding DNS entry",
    parameters: [PathParams.uuid(:id, "Alias ID")],
    responses: %{
      204 => {"Alias deleted successfully", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Alias not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, alias_record} <- Nodes.get_alias(id),
         {:ok, _} <- Nodes.delete_alias(alias_record) do
      send_resp(conn, :no_content, "")
    end
  end
end
