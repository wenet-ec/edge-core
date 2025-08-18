# edge_admin/lib/edge_admin_web/controllers/vpn/connection_controller.ex
defmodule EdgeAdminWeb.VPN.ConnectionController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.VPN
  alias EdgeAdminWeb.Schemas.VPN.ConnectionSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas
  action_fallback(EdgeAdminWeb.FallbackController)

  tags(["VPN.Connection"])

  operation(:show,
    summary: "Get VPN connection status",
    description: "Retrieve the current VPN connection status and details",
    responses: %{
      200 =>
        {"VPN connection details", "application/json", ConnectionSchemas.ConnectionSingleResponse}
    }
  )

  def show(conn, _params) do
    case VPN.get_connection() do
      {:ok, connection} ->
        render(conn, :show, connection: connection)

      {:error, :not_found} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to retrieve VPN connection status"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to retrieve VPN connection status", details: inspect(reason)})
    end
  end

  operation(:update,
    summary: "Update VPN connection",
    description: "Update VPN connection properties and settings",
    request_body:
      {"VPN connection update parameters", "application/json",
       ConnectionSchemas.ConnectionUpdateRequest},
    responses: %{
      200 =>
        {"VPN connection updated successfully", "application/json",
         ConnectionSchemas.ConnectionSingleResponse},
      400 => {"Invalid request", "application/json", CommonSchemas.GenericErrorResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def update(conn, params) do
    case VPN.update_connection_from_params(params) do
      {:ok, connection} ->
        conn
        |> put_status(:ok)
        |> render(:show, connection: connection)

      {:error, :invalid_params} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Invalid request",
          message: "Only 'manual_disconnect' field is allowed for updates and must be a boolean"
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to update VPN connection", details: inspect(reason)})
    end
  end
end
