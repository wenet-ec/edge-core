# edge_admin/lib/edge_admin_web/controllers/nodes/cluster_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.ClusterController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.ClusterSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug DegradedMode, :block when action in [:create, :update, :delete]
  plug DegradedMode, :allow when action in [:index, :show]

  tags(["Nodes.Cluster"])

  operation(:index,
    summary: "List all clusters",
    description: "Returns a paginated list of all edge clusters with filtering and sorting",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort(order_by_example: "inserted_at,name", order_directions_example: "desc,asc") ++
        [
          QueryParams.string_filter(:name,
            description:
              "Filter by cluster name — exact match or wildcard (prod*, *tion, *rod*). Use names for multi-cluster IN matching."
          ),
          QueryParams.string_array_filter(:names,
            description:
              "Filter by cluster names — comma-separated list for exact IN match (e.g. prod,staging). No wildcards; use name for wildcard filtering."
          ),
          QueryParams.uuid_array_filter(:node_ids,
            description:
              "Filter clusters by node membership — returns all distinct clusters containing any of the given node IDs (comma-separated UUIDs)."
          ),
          QueryParams.string_filter(:ipv4_range, description: "Filter by IPv4 range (exact match or wildcard)"),
          QueryParams.int_filter(:node_limit, description: "Filter by exact node limit", minimum: 1),
          QueryParams.boolean_filter(:has_node_limit,
            description:
              "Filter by whether a node limit is set: true returns clusters with a limit, false returns unlimited"
          )
        ] ++
        QueryParams.int_range_filter(:node_count) ++
        QueryParams.int_range_filter(:node_limit, minimum: 1) ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
    responses: %{
      200 => {"Paginated cluster list", "application/json", ClusterSchemas.ClusterPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {clusters, meta}} <- Nodes.list_clusters(params) do
      render(conn, :index, conn: conn, clusters: clusters, meta: meta)
    end
  end

  operation(:show,
    summary: "Get a specific cluster",
    description: "Returns details for a specific cluster by name",
    parameters: [PathParams.cluster_name(:name, "Cluster name")],
    responses: %{
      200 => {"Cluster details", "application/json", ClusterSchemas.ClusterSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{name: name}) do
    with {:ok, cluster} <- Nodes.get_cluster(name) do
      render(conn, :show, conn: conn, cluster: cluster)
    end
  end

  operation(:create,
    summary: "Create a new cluster",
    description:
      "Create a new edge cluster with optional IP range. The name `default` is reserved (used as a URL keyword on convenience routes) and will be rejected with HTTP 422.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    request_body:
      {"Cluster creation parameters", "application/json", ClusterSchemas.ClusterCreateRequest, required: true},
    responses: %{
      201 => {"Cluster created successfully", "application/json", ClusterSchemas.ClusterSingleResponse},
      409 =>
        {"Cluster name already exists, or IP range conflicts with an existing cluster", "application/json",
         CommonSchemas.ConflictResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Netmaker unavailable or in degraded mode", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create(conn, params) do
    with {:ok, cluster} <- Nodes.create_cluster(Map.merge(params, conn.body_params)),
         {:ok, cluster} <- Nodes.get_cluster(cluster.name) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/clusters/#{cluster.name}")
      |> render(:show, conn: conn, cluster: cluster)
    end
  end

  operation(:update,
    summary: "Update a cluster",
    description:
      "Update a cluster's settings. Only provided fields are changed. Pass null to unset a nullable field.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [PathParams.cluster_name(:name, "Cluster name")],
    request_body:
      {"Cluster update parameters", "application/json", ClusterSchemas.ClusterUpdateRequest, required: true},
    responses: %{
      200 => {"Cluster updated successfully", "application/json", ClusterSchemas.ClusterSingleResponse},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 =>
        {"Validation error or node_limit below current node count", "application/json",
         CommonSchemas.ChangesetErrorResponse},
      503 => {"Netmaker unavailable or in degraded mode", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def update(conn, %{name: name} = params) do
    with {:ok, cluster} <- Nodes.get_cluster(name),
         {:ok, updated_cluster} <- Nodes.update_cluster(cluster, Map.merge(params, conn.body_params)) do
      render(conn, :show, conn: conn, cluster: updated_cluster)
    end
  end

  operation(:delete,
    summary: "Delete a cluster",
    description:
      "Delete an empty cluster (must have no nodes).\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [PathParams.cluster_name(:name, "Cluster name")],
    responses: %{
      204 => {"Cluster deleted successfully", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      409 => {"Cannot delete cluster with nodes", "application/json", CommonSchemas.ConflictResponse},
      503 => {"Netmaker unavailable or in degraded mode", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def delete(conn, %{name: name}) do
    with {:ok, cluster} <- Nodes.get_cluster(name),
         {:ok, _cluster} <- Nodes.delete_cluster(cluster) do
      send_resp(conn, :no_content, "")
    end
  end
end
