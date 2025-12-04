# edge_admin_web/lib/edge_admin_web/controllers/nodes/cluster_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.ClusterController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.ClusterSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Nodes.Cluster"])

  operation(:index,
    summary: "List all clusters",
    description: "Returns a paginated list of all edge clusters with filtering and sorting",
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
      ipv4_range: [
        in: :query,
        description: "Filter by IPv4 range (text search, supports partial matches)",
        schema: %OpenApiSpex.Schema{type: :string},
      ],
      node_count: [
        in: :query,
        description:
          "Filter by node count (exact match or range queries: gte:5, gt:5, lte:10, lt:10)",
        schema: %OpenApiSpex.Schema{type: :string},
      ]
    ],
    responses: %{
      200 =>
        {"Paginated cluster list", "application/json", ClusterSchemas.ClusterPaginatedResponse}
    }
  )

  def index(conn, params) do
    page_result = Nodes.list_clusters_with_filtering_pagination(params)
    render(conn, :index, page_result: page_result)
  end

  operation(:show,
    summary: "Get a specific cluster",
    description: "Returns details for a specific cluster by name",
    parameters: [
      name: [
        in: :path,
        description: "Cluster name",
        schema: %OpenApiSpex.Schema{type: :string, pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"}
      ]
    ],
    responses: %{
      200 => {"Cluster details", "application/json", ClusterSchemas.ClusterSingleResponse},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"name" => name}) do
    cluster = Nodes.get_cluster!(name)
    render(conn, :show, cluster: cluster)
  end

  operation(:create,
    summary: "Create a new cluster",
    description: "Create a new edge cluster with optional IP range",
    request_body:
      {"Cluster creation parameters", "application/json", ClusterSchemas.ClusterCreateRequest},
    responses: %{
      201 =>
        {"Cluster created successfully", "application/json", ClusterSchemas.ClusterSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def create(conn, %{"cluster" => cluster_params}) do
    with {:ok, cluster} <- Nodes.create_cluster(cluster_params) do
      # Reload with node_count
      cluster = Nodes.get_cluster!(cluster.name)

      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/clusters/#{cluster.name}")
      |> render(:show, cluster: cluster)
    end
  end

  operation(:delete,
    summary: "Delete a cluster",
    description: "Delete an empty cluster (must have no nodes)",
    parameters: [
      name: [
        in: :path,
        description: "Cluster name",
        schema: %OpenApiSpex.Schema{type: :string, pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"}
      ]
    ],
    responses: %{
      204 => "Cluster deleted successfully",
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Cannot delete cluster with nodes", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def delete(conn, %{"name" => name}) do
    cluster = Nodes.get_cluster!(name)

    with {:ok, _cluster} <- Nodes.delete_cluster(cluster) do
      send_resp(conn, :no_content, "")
    end
  end
end
