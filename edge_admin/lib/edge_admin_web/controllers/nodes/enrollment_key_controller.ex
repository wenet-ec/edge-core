# edge_admin/lib/edge_admin_web/controllers/nodes/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Policies.EnrollmentKeyPolicy
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode,
       :block when action in [:create, :create_for_default, :create_for_public, :delete, :update]

  tags(["Nodes.EnrollmentKey"])

  operation(:index,
    summary: "List enrollment keys",
    description: "Returns a paginated list of enrollment keys with filtering and sorting.",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort() ++
        [
          QueryParams.string_filter(:cluster_name,
            description: "Filter by cluster name (exact match or wildcard: prod*, *east, etc.)"
          ),
          QueryParams.string_filter(:name,
            description: "Filter by enrollment key name (case-insensitive substring or wildcard: prod*, *rollout, etc.)"
          ),
          QueryParams.boolean_filter(:has_name,
            description:
              "Filter by whether the key has a name set: true returns keys with a human-readable label, false returns unlabeled keys (e.g. those issued by the public/default-cluster endpoint)"
          ),
          QueryParams.string_filter(:key, description: "Filter by exact key value"),
          QueryParams.int_filter(:uses_remaining,
            description:
              "Filter by exact uses_remaining (positive integer; use is_unlimited=true to find unlimited keys)",
            minimum: 1
          ),
          QueryParams.boolean_filter(:is_unlimited,
            description:
              "Filter by whether the key has unlimited uses: true returns unlimited keys (uses_remaining is null), false returns keys with a finite use count"
          ),
          QueryParams.boolean_filter(:is_spent,
            description:
              "Filter by whether the key is exhausted: true returns keys with uses_remaining == 0, false returns keys with uses remaining"
          ),
          QueryParams.boolean_filter(:is_expired,
            description:
              "Filter by whether the key is expired: true returns keys where expires_at is in the past, false returns active keys (including those with no expiry)"
          ),
          QueryParams.boolean_filter(:is_never_used,
            description:
              "Filter by whether the key has never been used: true returns keys where last_used_at is null, false returns keys that have been used at least once"
          ),
          QueryParams.boolean_filter(:has_expiry,
            description:
              "Filter by whether the key has an expiry set: true returns keys with expires_at present, false returns keys with no expiry (unlimited lifetime)"
          )
        ] ++
        QueryParams.int_range_filter(:uses_remaining, minimum: 1) ++
        QueryParams.datetime_range_filter(:expires_at) ++
        QueryParams.datetime_range_filter(:last_used_at) ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
    responses: %{
      200 => {"Paginated enrollment key list", "application/json", EnrollmentKeySchemas.EnrollmentKeyPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {keys, meta}} <- Nodes.list_enrollment_keys(params) do
      render(conn, :index, conn: conn, enrollment_keys: keys, meta: meta)
    end
  end

  operation(:show,
    summary: "Get an enrollment key",
    description: "Returns details for a specific enrollment key by ID",
    parameters: [PathParams.uuid(:id, "Enrollment key ID")],
    responses: %{
      200 => {"Enrollment key", "application/json", EnrollmentKeySchemas.EnrollmentKeySingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, key} <- Nodes.get_enrollment_key(id) do
      render(conn, :show, conn: conn, enrollment_key: key)
    end
  end

  operation(:create,
    summary: "Create an enrollment key for a cluster",
    description: """
    Create a new enrollment key for an edge cluster. The returned `key` blob must be set as the `ENROLLMENT_KEY`
    environment variable on the agent to allow it to join the cluster's VPN network.

    Keys can be limited by use count (`uses_remaining`) or by expiry time (`expires_at`). Omit both for a single-use key with no expiry.

    **Note:** This endpoint is unavailable during degraded mode (503).
    """,
    parameters: [PathParams.cluster_name(:cluster_name, "Cluster name")],
    request_body: {"Enrollment key parameters", "application/json", EnrollmentKeySchemas.EnrollmentKeyCreateRequest},
    responses: %{
      201 => {"Enrollment key created", "application/json", EnrollmentKeySchemas.EnrollmentKeySingleResponse},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create(conn, %{cluster_name: cluster_name} = params) do
    with {:ok, cluster} <- Nodes.get_cluster(cluster_name),
         {:ok, key} <- Nodes.create_enrollment_key(cluster, Map.merge(params, conn.body_params)) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/enrollment_keys/#{key.id}")
      |> render(:show, conn: conn, enrollment_key: key)
    end
  end

  operation(:create_for_default,
    summary: "Create an enrollment key for the default cluster",
    description:
      "Convenience endpoint for the default cluster (configured via DEFAULT_CLUSTER_NAME env).\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    request_body: {"Enrollment key parameters", "application/json", EnrollmentKeySchemas.EnrollmentKeyCreateRequest},
    responses: %{
      201 => {"Enrollment key created", "application/json", EnrollmentKeySchemas.EnrollmentKeySingleResponse},
      403 => {"Default cluster not configured", "application/json", CommonSchemas.ForbiddenResponse},
      404 => {"Default cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create_for_default(conn, params) do
    with :ok <- EnrollmentKeyPolicy.authorize(:create_for_default),
         {:ok, cluster} <- Nodes.get_cluster(EnrollmentKeyPolicy.default_cluster_name()),
         {:ok, key} <- Nodes.create_enrollment_key(cluster, Map.merge(params, conn.body_params)) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/enrollment_keys/#{key.id}")
      |> render(:show, conn: conn, enrollment_key: key)
    end
  end

  operation(:create_for_public,
    summary: "Get a public enrollment key for the default cluster",
    description: """
    Public endpoint (no authentication required). Only enabled when both
    PUBLIC_ENROLLMENT_KEY_ENABLED=true and DEFAULT_CLUSTER_NAME are configured.

    **Note:** This endpoint is unavailable during degraded mode (503).
    """,
    responses: %{
      201 => {"Enrollment key created", "application/json", EnrollmentKeySchemas.EnrollmentKeySingleResponse},
      403 => {"Public enrollment disabled", "application/json", CommonSchemas.ForbiddenResponse},
      404 => {"Default cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create_for_public(conn, _params) do
    with :ok <- EnrollmentKeyPolicy.authorize(:create_for_public),
         {:ok, cluster} <- Nodes.get_cluster(EnrollmentKeyPolicy.default_cluster_name()),
         {:ok, key} <- Nodes.create_enrollment_key(cluster, %{}) do
      conn
      |> put_status(:created)
      |> render(:show, conn: conn, enrollment_key: key)
    end
  end

  operation(:update,
    summary: "Update an enrollment key",
    description:
      "Update expires_at or uses_remaining. Pass null to unset a nullable field.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [PathParams.uuid(:id, "Enrollment key ID")],
    request_body: {"Update parameters", "application/json", EnrollmentKeySchemas.EnrollmentKeyUpdateRequest},
    responses: %{
      200 => {"Updated enrollment key", "application/json", EnrollmentKeySchemas.EnrollmentKeySingleResponse},
      404 => {"Not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def update(conn, %{id: id} = params) do
    with {:ok, key} <- Nodes.get_enrollment_key(id),
         {:ok, updated_key} <- Nodes.update_enrollment_key(key, Map.merge(params, conn.body_params)) do
      render(conn, :show, conn: conn, enrollment_key: updated_key)
    end
  end

  operation(:delete,
    summary: "Delete an enrollment key",
    description:
      "Permanently deletes an enrollment key. **Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [PathParams.uuid(:id, "Enrollment key ID")],
    responses: %{
      204 => {"Enrollment key deleted", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, key} <- Nodes.get_enrollment_key(id),
         {:ok, _} <- Nodes.delete_enrollment_key(key) do
      send_resp(conn, :no_content, "")
    end
  end
end
