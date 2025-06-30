# edge_admin/lib/edge_admin_web/controllers/nodes/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Nodes.EnrollmentKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Tailscale
  alias EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.FallbackController)

  tags ["Nodes.EnrollmentKey"]

  operation :create,
    summary: "Create enrollment key",
    description: "Generate a new enrollment key for edge nodes to join the VPN",
    responses: %{
      201 =>
        {"Enrollment key created", "application/json", EnrollmentKeySchemas.EnrollmentKeyResponse},
      500 => {"VPN service error", "application/json", CommonSchemas.GenericErrorResponse},
      503 => {"VPN service unavailable", "application/json", CommonSchemas.GenericErrorResponse}
    }

  def create(conn, _params) do
    case Tailscale.create_enrollment_key() do
      {:ok, enrollment_data} ->
        conn
        |> put_status(:created)
        |> render(:show, enrollment_key: enrollment_data)

      {:error, :vpn_service_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "VPN service is currently unavailable"})

      {:error, :user_not_found} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "edge-nodes user not found in VPN system"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to create enrollment key", details: inspect(reason)})
    end
  end
end
