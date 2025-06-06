# edge_admin/lib/edge_admin_web/controllers/vpn/connection_controller.ex
defmodule EdgeAdminWeb.VPN.ConnectionController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.VPN
  alias EdgeAdminWeb.Schemas.VPN.ConnectionSchemas

  action_fallback EdgeAdminWeb.FallbackController

  tags ["VPN"]

  @doc """
  Get VPN connection status
  """
  operation :show,
    summary: "Get VPN connection status",
    description: "Returns the current VPN connection status and details",
    responses: %{
      200 => {"VPN connection status", "application/json", ConnectionSchemas.ConnectionResponse},
      500 => {"Internal server error", "application/json", ConnectionSchemas.ErrorResponse}
    }

  def show(conn, _params) do
    case VPN.get_connection() do
      {:ok, connection} ->
        conn
        |> put_status(:ok)
        |> render(:show, connection: connection)

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to retrieve VPN connection status"})
    end
  end

  @doc """
  Update VPN connection manual disconnect setting
  """
  operation :update,
    summary: "Update VPN manual disconnect setting",
    description: "Update the manual disconnect flag to control auto-reconnection behavior",
    request_body: {"Connection update", "application/json", ConnectionSchemas.UpdateRequest},
    responses: %{
      200 => {"Updated VPN connection", "application/json", ConnectionSchemas.ConnectionResponse},
      400 => {"Bad request", "application/json", ConnectionSchemas.ErrorResponse},
      422 => {"Validation error", "application/json", ConnectionSchemas.ErrorResponse},
      500 => {"Internal server error", "application/json", ConnectionSchemas.ErrorResponse}
    }

  def update(conn, %{"manual_disconnect" => manual_disconnect} = _params) when is_boolean(manual_disconnect) do
    case VPN.update_connection(%{manual_disconnect: manual_disconnect}) do
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
