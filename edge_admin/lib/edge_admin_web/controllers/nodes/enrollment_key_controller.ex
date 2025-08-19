# edge_admin/lib/edge_admin_web/controllers/nodes/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Nodes.EnrollmentKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.VPN
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas

  action_fallback(EdgeAdminWeb.FallbackController)

  tags ["Nodes.EnrollmentKey"]

  operation :create,
    summary: "Create enrollment key",
    description: "Generate a new enrollment key for edge nodes to join the VPN",
    responses: %{
      201 => {"Enrollment key created", "application/json", EnrollmentKeySchemas.EnrollmentKeyResponse},
      500 => {"VPN service error", "application/json", CommonSchemas.GenericErrorResponse},
      503 => {"VPN service unavailable", "application/json", CommonSchemas.GenericErrorResponse}
    }

  def create(conn, _params) do
    case VPN.create_enrollment_key_with_error_handling() do
      {:ok, enrollment_data} ->
        conn
        |> put_status(:created)
        |> render(:show, enrollment_key: enrollment_data)

      {:error, :vpn_service_unavailable, message} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: message})

      {:error, :internal_server_error, message} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: message})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to create enrollment key", details: inspect(reason)})
    end
  end
end
