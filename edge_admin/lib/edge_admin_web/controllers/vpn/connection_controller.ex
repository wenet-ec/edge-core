# edge_admin/lib/edge_admin_web/controllers/vpn/connection_controller.ex
defmodule EdgeAdminWeb.VPN.ConnectionController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Tailscale
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
    case Tailscale.get_connection() do
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

  def update(conn, %{"manual_disconnect" => true} = _params) do
    # Perform manual disconnect operation
    case Tailscale.disconnect_from_vpn_manual() do
      {:ok, connection} ->
        conn
        |> put_status(:ok)
        |> render(:show, connection: connection)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to disconnect from VPN", details: inspect(reason)})
    end
  end

  def update(conn, %{"manual_disconnect" => false} = _params) do
    # For manual_disconnect: false, just update the flag without reconnecting
    # (reconnection should be handled by auto-reconnection worker)
    case Tailscale.update_connection(%{manual_disconnect: false}) do
      {:ok, connection} ->
        conn
        |> put_status(:ok)
        |> render(:show, connection: connection)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to update VPN connection", details: inspect(reason)})
    end
  end

  def update(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "Invalid request",
      message: "Only 'manual_disconnect' field is allowed for updates and must be a boolean"
    })
  end
end
