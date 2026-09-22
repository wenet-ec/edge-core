# edge_admin/lib/edge_admin_web/controllers/ingress_tunneling/tunnel_connection_controller.ex
defmodule EdgeAdminWeb.Controllers.IngressTunneling.TunnelConnectionController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.IngressTunneling.TunnelConnectionSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]
  tags(["IngressTunneling.TunnelConnection"])

  operation(:index,
    summary: "List Tunnel Connections",
    description: "Returns a paginated list of Tunnel Client connections to Ingress Nodes.",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort() ++
        [
          QueryParams.uuid_in_filter(:tunnel_client_id),
          QueryParams.uuid_in_filter(:node_id)
        ],
    responses: %{
      200 =>
        {"Paginated Tunnel Connection list", "application/json",
         TunnelConnectionSchemas.TunnelConnectionPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {connections, meta}} <- IngressTunneling.list_tunnel_connections(params) do
      render(conn, :index, conn: conn, tunnel_connections: connections, meta: meta)
    end
  end

  operation(:create,
    summary: "Create Tunnel Connection",
    description:
      "Creates one connection for an existing Tunnel Client and allocates addresses in the selected Ingress Node's isolated address pool.",
    parameters: [PathParams.uuid(:tunnel_client_id, "Tunnel Client ID")],
    request_body:
      {"Tunnel Connection creation data", "application/json", TunnelConnectionSchemas.TunnelConnectionCreateRequest,
       required: true},
    responses: %{
      201 => {"Tunnel Connection created", "application/json", TunnelConnectionSchemas.TunnelConnectionSingleResponse},
      400 => {"Invalid request parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Tunnel Client or Node not found", "application/json", CommonSchemas.NotFoundResponse},
      409 => {"Connection conflict", "application/json", CommonSchemas.ConflictResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def create(conn, %{tunnel_client_id: client_id} = params) do
    with {:ok, connection} <- IngressTunneling.create_tunnel_connection(client_id, Map.merge(params, conn.body_params)) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/tunnel_connections/#{connection.id}")
      |> render(:show, conn: conn, tunnel_connection: connection)
    end
  end

  operation(:show,
    summary: "Get Tunnel Connection",
    description: "Returns one Tunnel Connection and its allocated addresses.",
    parameters: [PathParams.uuid(:id, "Tunnel Connection ID")],
    responses: %{
      200 => {"Tunnel Connection", "application/json", TunnelConnectionSchemas.TunnelConnectionSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Tunnel Connection not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, connection} <- IngressTunneling.get_tunnel_connection(id) do
      render(conn, :show, conn: conn, tunnel_connection: connection)
    end
  end

  operation(:delete,
    summary: "Delete Tunnel Connection",
    description: "Permanently deletes a Tunnel Connection and releases its database allocation.",
    parameters: [PathParams.uuid(:id, "Tunnel Connection ID")],
    responses: %{
      204 => {"Tunnel Connection deleted", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Tunnel Connection not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, connection} <- IngressTunneling.get_tunnel_connection(id),
         {:ok, %TunnelConnection{}} <- IngressTunneling.delete_tunnel_connection(connection) do
      send_resp(conn, :no_content, "")
    end
  end
end
