# edge_admin_web/lib/edge_admin_web/controllers/nodes/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Policies.EnrollmentKeyPolicy
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  plug EdgeAdminWeb.Plugs.DegradedMode,
       :block when action in [:create, :create_for_default, :create_for_public, :delete, :update]

  tags(["Nodes.EnrollmentKey"])

  operation(:index,
    summary: "List enrollment keys",
    description: "Returns a paginated list of enrollment keys with filtering and sorting.",
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
        example: "inserted_at"
      ],
      order_directions: [
        in: :query,
        description: "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc"
      ],
      cluster_name: [
        in: :query,
        description: "Filter by cluster name (exact match or wildcard: prod*, *east, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      key: [
        in: :query,
        description: "Filter by exact key value",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      uses_remaining: [
        in: :query,
        description: "Filter by exact uses_remaining (positive integer; use is_unlimited=true to find unlimited keys)",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1}
      ],
      uses_remaining__gte: [
        in: :query,
        description: "Filter by minimum uses_remaining",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1}
      ],
      uses_remaining__lte: [
        in: :query,
        description: "Filter by maximum uses_remaining",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1}
      ],
      is_unlimited: [
        in: :query,
        description:
          "Filter by whether the key has unlimited uses: true returns unlimited keys (uses_remaining is null), false returns keys with a finite use count",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      is_spent: [
        in: :query,
        description:
          "Filter by whether the key is exhausted: true returns keys with uses_remaining == 0, false returns keys with uses remaining",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      is_expired: [
        in: :query,
        description:
          "Filter by whether the key is expired: true returns keys where expired_at is in the past, false returns active keys (including those with no expiry)",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      expired_at__gte: [
        in: :query,
        description:
          "Filter keys expiring after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      expired_at__lte: [
        in: :query,
        description:
          "Filter keys expiring before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      last_used_at__gte: [
        in: :query,
        description:
          "Filter keys last used after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      last_used_at__lte: [
        in: :query,
        description:
          "Filter keys last used before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      inserted_at__gte: [
        in: :query,
        description:
          "Filter keys created after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      inserted_at__lte: [
        in: :query,
        description:
          "Filter keys created before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      updated_at__gte: [
        in: :query,
        description:
          "Filter keys updated after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      updated_at__lte: [
        in: :query,
        description:
          "Filter keys updated before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ]
    ],
    responses: %{
      200 => {"Paginated enrollment key list", "application/json", EnrollmentKeySchemas.EnrollmentKeyPaginatedResponse},
      422 => {"Invalid query parameters", "application/json", OpenApiSpex.JsonErrorResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {keys, meta}} <- Nodes.list_enrollment_keys(params) do
      render(conn, :index, enrollment_keys: keys, meta: meta)
    end
  end

  operation(:show,
    summary: "Get an enrollment key",
    description: "Returns details for a specific enrollment key by ID",
    parameters: [
      id: [in: :path, description: "Enrollment key ID", schema: %OpenApiSpex.Schema{type: :string, format: :uuid}]
    ],
    responses: %{
      200 => {"Enrollment key", "application/json", EnrollmentKeySchemas.EnrollmentKeySingleResponse},
      404 => {"Not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Invalid path parameters", "application/json", OpenApiSpex.JsonErrorResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, key} <- Nodes.get_enrollment_key(id) do
      render(conn, :show, enrollment_key: key)
    end
  end

  operation(:create,
    summary: "Create an enrollment key for a cluster",
    description: "**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [
      cluster_name: [
        in: :path,
        description: "Cluster name",
        schema: %OpenApiSpex.Schema{type: :string, pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", maxLength: 24}
      ]
    ],
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
      |> render(:show, enrollment_key: key)
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
      |> render(:show, enrollment_key: key)
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
      |> render(:show, enrollment_key: key)
    end
  end

  operation(:update,
    summary: "Update an enrollment key",
    description:
      "Update expired_at or uses_remaining. Pass null to unset a nullable field.\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [
      id: [in: :path, description: "Enrollment key ID", schema: %OpenApiSpex.Schema{type: :string, format: :uuid}]
    ],
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
      render(conn, :show, enrollment_key: updated_key)
    end
  end

  operation(:delete,
    summary: "Delete an enrollment key",
    description:
      "Permanently deletes an enrollment key. **Note:** This endpoint is unavailable during degraded mode (503).",
    parameters: [
      id: [in: :path, description: "Enrollment key ID", schema: %OpenApiSpex.Schema{type: :string, format: :uuid}]
    ],
    responses: %{
      204 => {"Enrollment key deleted", "", nil},
      404 => {"Not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Invalid path parameters", "application/json", OpenApiSpex.JsonErrorResponse},
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
