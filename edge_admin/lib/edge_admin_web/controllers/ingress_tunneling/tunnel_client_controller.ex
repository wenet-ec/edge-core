# edge_admin/lib/edge_admin_web/controllers/ingress_tunneling/tunnel_client_controller.ex
defmodule EdgeAdminWeb.Controllers.IngressTunneling.TunnelClientController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.IngressTunneling.TunnelClientSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

  tags(["IngressTunneling.TunnelClient"])

  operation(:index,
    summary: "List Tunnel Clients",
    description: "Returns a paginated list of Admin-managed Tunnel Client identities.",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort() ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
    responses: %{
      200 => {"Paginated Tunnel Client list", "application/json", TunnelClientSchemas.TunnelClientPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {tunnel_clients, meta}} <- IngressTunneling.list_tunnel_clients(params) do
      render(conn, :index, conn: conn, tunnel_clients: tunnel_clients, meta: meta)
    end
  end

  operation(:create,
    summary: "Create Tunnel Client",
    description:
      "Generates and persists a new Admin-owned X25519 WireGuard identity. Its private key remains encrypted at rest and is never included in an API response.",
    responses: %{
      201 => {"Tunnel Client created", "application/json", TunnelClientSchemas.TunnelClientSingleResponse}
    }
  )

  def create(conn, _params) do
    with {:ok, %TunnelClient{} = tunnel_client} <- IngressTunneling.create_tunnel_client() do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/tunnel_clients/#{tunnel_client.id}")
      |> render(:show, conn: conn, tunnel_client: tunnel_client)
    end
  end

  operation(:show,
    summary: "Get Tunnel Client",
    description: "Returns one Tunnel Client's public identity. The private key is never returned by the API.",
    parameters: [PathParams.uuid(:id, "Tunnel Client ID")],
    responses: %{
      200 => {"Tunnel Client", "application/json", TunnelClientSchemas.TunnelClientSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Tunnel Client not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, tunnel_client} <- IngressTunneling.get_tunnel_client(id) do
      render(conn, :show, conn: conn, tunnel_client: tunnel_client)
    end
  end

  operation(:delete,
    summary: "Delete Tunnel Client",
    description: "Permanently deletes a Tunnel Client and its dependent Tunnel Connections.",
    parameters: [PathParams.uuid(:id, "Tunnel Client ID")],
    responses: %{
      204 => {"Tunnel Client deleted", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Tunnel Client not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, tunnel_client} <- IngressTunneling.get_tunnel_client(id),
         {:ok, %TunnelClient{}} <- IngressTunneling.delete_tunnel_client(tunnel_client) do
      send_resp(conn, :no_content, "")
    end
  end
end
