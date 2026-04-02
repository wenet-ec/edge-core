# edge_admin_web/lib/edge_admin_web/controllers/nodes/cluster_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.ClusterController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.ClusterSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug DegradedMode, :block when action in [:create, :update, :delete]
  plug DegradedMode, :allow when action in [:index, :show]

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
      order_by: [
        in: :query,
        description: "Comma-separated list of fields to sort by",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at,name"
      ],
      order_directions: [
        in: :query,
        description: "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc,asc"
      ],
      name: [
        in: :query,
        description: "Filter by cluster name (exact match or wildcard: prod*, *tion, *rod*)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      ipv4_range: [
        in: :query,
        description: "Filter by IPv4 range (exact match or wildcard)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      inserted_at__gte: [
        in: :query,
        description:
          "Filter clusters inserted after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{anyOf: [%OpenApiSpex.Schema{type: :string, format: :"date-time"}, %OpenApiSpex.Schema{type: :string, format: :date}]}
      ],
      inserted_at__lte: [
        in: :query,
        description:
          "Filter clusters inserted before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{anyOf: [%OpenApiSpex.Schema{type: :string, format: :"date-time"}, %OpenApiSpex.Schema{type: :string, format: :date}]}
      ],
      node_count__gte: [
        in: :query,
        description: "Filter by minimum node count",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 0}
      ],
      node_count__lte: [
        in: :query,
        description: "Filter by maximum node count",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 0}
      ],
      node_limit: [
        in: :query,
        description: "Filter by exact node limit",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1}
      ],
      has_node_limit: [
        in: :query,
        description:
          "Filter by whether a node limit is set: true returns clusters with a limit, false returns unlimited clusters",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      node_limit__gte: [
        in: :query,
        description: "Filter by minimum node limit",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1}
      ],
      node_limit__lte: [
        in: :query,
        description: "Filter by maximum node limit",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1}
      ]
    ],
    responses: %{
      200 => {"Paginated cluster list", "application/json", ClusterSchemas.ClusterPaginatedResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {clusters, meta}} <- Nodes.list_clusters(params) do
      render(conn, :index, clusters: clusters, meta: meta)
    end
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
    with {:ok, cluster} <- Nodes.get_cluster(name) do
      render(conn, :show, cluster: cluster)
    end
  end

  operation(:create,
    summary: "Create a new cluster",
    description:
      "Create a new edge cluster with optional IP range.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    request_body: {"Cluster creation parameters", "application/json", ClusterSchemas.ClusterCreateRequest},
    responses: %{
      201 => {"Cluster created successfully", "application/json", ClusterSchemas.ClusterSingleResponse},
      409 =>
        {"Cluster name already exists, or IP range conflicts with an existing cluster", "application/json",
         CommonSchemas.ConflictResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create(conn, params) do
    with {:ok, cluster} <- Nodes.create_cluster(params),
         {:ok, cluster} <- Nodes.get_cluster(cluster.name) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/clusters/#{cluster.name}")
      |> render(:show, cluster: cluster)
    end
  end

  operation(:update,
    summary: "Update a cluster",
    description:
      "Update a cluster's settings. Only provided fields are changed. Pass null to unset a nullable field.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [
      name: [
        in: :path,
        description: "Cluster name",
        schema: %OpenApiSpex.Schema{type: :string, pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"}
      ]
    ],
    request_body: {"Cluster update parameters", "application/json", ClusterSchemas.ClusterUpdateRequest},
    responses: %{
      200 => {"Cluster updated successfully", "application/json", ClusterSchemas.ClusterSingleResponse},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 =>
        {"Validation error or node_limit below current node count", "application/json",
         CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def update(conn, %{"name" => name} = params) do
    with {:ok, cluster} <- Nodes.get_cluster(name),
         {:ok, updated_cluster} <- Nodes.update_cluster(cluster, params) do
      render(conn, :show, cluster: updated_cluster)
    end
  end

  operation(:delete,
    summary: "Delete a cluster",
    description:
      "Delete an empty cluster (must have no nodes).\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [
      name: [
        in: :path,
        description: "Cluster name",
        schema: %OpenApiSpex.Schema{type: :string, pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"}
      ]
    ],
    responses: %{
      204 => {"Cluster deleted successfully", "", nil},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      409 => {"Cannot delete cluster with nodes", "application/json", CommonSchemas.ConflictResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def delete(conn, %{"name" => name}) do
    with {:ok, cluster} <- Nodes.get_cluster(name),
         {:ok, _cluster} <- Nodes.delete_cluster(cluster) do
      send_resp(conn, :no_content, "")
    end
  end
end
