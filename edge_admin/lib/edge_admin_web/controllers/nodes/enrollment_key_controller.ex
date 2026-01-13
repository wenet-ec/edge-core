# edge_admin_web/lib/edge_admin_web/controllers/nodes/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :block when action in [:create, :create_for_default, :create_for_public]

  tags(["Nodes.EnrollmentKey"])

  operation(:create,
    summary: "Get enrollment key for cluster",
    description: """
    Creates or retrieves an enrollment key for a cluster.

    **Default**: Retrieves the Netmaker auto-generated default key (unlimited uses, no expiration).
    Use for production edge nodes and mass deployments.

    **Custom**: Creates a new key with user-specified expiry and uses (not tracked in DB, tagged for audit trail).
    Use for controlled/time-limited registrations.

    **Note:** This endpoint is unavailable during degraded mode (503).
    """,
    parameters: [
      name: [
        in: :path,
        description: "Cluster name",
        schema: %OpenApiSpex.Schema{type: :string, pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"}
      ]
    ],
    request_body: {"Enrollment key parameters", "application/json", EnrollmentKeySchemas.EnrollmentKeyCreateRequest},
    responses: %{
      201 => {"Enrollment key retrieved/created", "application/json", EnrollmentKeySchemas.EnrollmentKeyResponse},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create(conn, %{"name" => cluster_name} = params) do
    with {:ok, cluster} <- Nodes.get_cluster(cluster_name),
         {:ok, enrollment_key} <- Nodes.create_enrollment_key(cluster, params) do
      conn
      |> put_status(:created)
      |> render(:show, enrollment_key: enrollment_key)
    end
  end

  operation(:create_for_default,
    summary: "Get enrollment key for default cluster",
    description:
      "Convenience endpoint that gets an enrollment key for the default cluster (configured via DEFAULT_CLUSTER_NAME env).\n\n**Note:** This endpoint is unavailable during degraded mode (503).",
    request_body: {"Enrollment key parameters", "application/json", EnrollmentKeySchemas.EnrollmentKeyCreateRequest},
    responses: %{
      201 => {"Enrollment key retrieved/created", "application/json", EnrollmentKeySchemas.EnrollmentKeyResponse},
      403 => {"Default cluster not configured", "application/json", CommonSchemas.ForbiddenResponse},
      404 => {"Default cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create_for_default(conn, params) do
    # Get default cluster name from config
    default_cluster_name = Application.get_env(:edge_admin, :default_cluster_name)

    if is_nil(default_cluster_name) do
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "Default cluster not configured",
        message: "DEFAULT_CLUSTER_NAME environment variable is not set"
      })
    else
      with {:ok, cluster} <- Nodes.get_cluster(default_cluster_name),
           {:ok, enrollment_key} <- Nodes.create_enrollment_key(cluster, params) do
        conn
        |> put_status(:created)
        |> render(:show, enrollment_key: enrollment_key)
      end
    end
  end

  operation(:create_for_public,
    summary: "Get public enrollment key for default cluster",
    description: """
    Public endpoint (no authentication required) that retrieves the default enrollment key
    for the default cluster. This endpoint is only enabled when both:
    - PUBLIC_ENROLLMENT_KEY_ENABLED=true
    - DEFAULT_CLUSTER_NAME is configured

    Use this for public/demo environments where agents can auto-enroll without pre-configured keys.

    **Note:** This endpoint is unavailable during degraded mode (503).
    """,
    responses: %{
      200 => {"Public enrollment key", "application/json", EnrollmentKeySchemas.EnrollmentKeyResponse},
      403 => {"Public enrollment disabled", "application/json", CommonSchemas.ForbiddenResponse},
      404 => {"Default cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create_for_public(conn, _params) do
    # Check if public enrollment is enabled
    public_enabled = Application.get_env(:edge_admin, :public_enrollment_key_enabled, false)
    default_cluster_name = Application.get_env(:edge_admin, :default_cluster_name)

    cond do
      not public_enabled ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "Public enrollment disabled",
          message: "PUBLIC_ENROLLMENT_KEY_ENABLED is not set to true"
        })

      is_nil(default_cluster_name) ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "Default cluster not configured",
          message: "DEFAULT_CLUSTER_NAME environment variable is not set"
        })

      true ->
        # Get default enrollment key (key_type: "default")
        with {:ok, cluster} <- Nodes.get_cluster(default_cluster_name),
             {:ok, enrollment_key} <-
               Nodes.create_enrollment_key(cluster, %{"enrollment_key" => %{"key_type" => "default"}}) do
          render(conn, :show, enrollment_key: enrollment_key)
        end
    end
  end
end
