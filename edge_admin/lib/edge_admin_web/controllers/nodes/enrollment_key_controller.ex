# edge_admin_web/lib/edge_admin_web/controllers/nodes/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Nodes.EnrollmentKey"])

  operation(:create,
    summary: "Get enrollment key for cluster",
    description: """
    Creates or retrieves an enrollment key for a cluster.

    **Default**: Retrieves the Netmaker auto-generated default key (unlimited uses, no expiration).
    Use for production edge nodes and mass deployments.

    **Custom**: Creates a new key with user-specified expiry and uses (not tracked in DB, tagged for audit trail).
    Use for controlled/time-limited registrations.

    **Ephemeral**: Creates a tracked key for automatic cleanup (configurable expiry/uses, tracked in DB).
    Use for temporary troubleshooting, testing, or demos.
    """,
    parameters: [
      name: [
        in: :path,
        description: "Cluster name",
        schema: %OpenApiSpex.Schema{type: :string, pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"}
      ]
    ],
    request_body:
      {"Enrollment key parameters", "application/json",
       EnrollmentKeySchemas.EnrollmentKeyCreateRequest},
    responses: %{
      201 =>
        {"Enrollment key retrieved/created", "application/json", EnrollmentKeySchemas.EnrollmentKeyResponse},
      404 => {"Cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def create(conn, %{"name" => cluster_name} = params) do
    enrollment_key_params = Map.get(params, "enrollment_key", %{})

    with {:ok, enrollment_key} <- Nodes.create_enrollment_key(cluster_name, enrollment_key_params) do
      conn
      |> put_status(:created)
      |> render(:show, enrollment_key: enrollment_key)
    end
  end

  operation(:create_for_default,
    summary: "Get enrollment key for default cluster",
    description:
      "Convenience endpoint that gets an enrollment key for the default cluster (configured via DEFAULT_CLUSTER_NAME env)",
    request_body:
      {"Enrollment key parameters", "application/json",
       EnrollmentKeySchemas.EnrollmentKeyCreateRequest},
    responses: %{
      201 =>
        {"Enrollment key retrieved/created", "application/json", EnrollmentKeySchemas.EnrollmentKeyResponse},
      400 => {"Default cluster not configured", "application/json", CommonSchemas.ErrorResponse},
      404 => {"Default cluster not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def create_for_default(conn, params) do
    enrollment_key_params = Map.get(params, "enrollment_key", %{})

    # Get default cluster name from config
    default_cluster_name = Application.get_env(:edge_admin, :default_cluster_name)

    if is_nil(default_cluster_name) do
      conn
      |> put_status(:bad_request)
      |> json(%{
        error: "Default cluster not configured",
        message: "DEFAULT_CLUSTER_NAME environment variable is not set"
      })
    else
      with {:ok, enrollment_key} <-
             Nodes.create_enrollment_key(default_cluster_name, enrollment_key_params) do
        conn
        |> put_status(:created)
        |> render(:show, enrollment_key: enrollment_key)
      end
    end
  end
end
