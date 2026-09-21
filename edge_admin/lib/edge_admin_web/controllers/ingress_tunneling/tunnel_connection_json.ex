# edge_admin/lib/edge_admin_web/controllers/ingress_tunneling/tunnel_connection_json.ex
defmodule EdgeAdminWeb.Controllers.IngressTunneling.TunnelConnectionJSON do
  alias EdgeAdmin.IngressTunneling.Views.TunnelConnectionView
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, tunnel_connections: connections, meta: meta}) do
    ResponseEnvelope.success(conn, Enum.map(connections, &TunnelConnectionView.render/1), meta)
  end

  def show(%{conn: conn, tunnel_connection: connection}) do
    ResponseEnvelope.success(conn, TunnelConnectionView.render(connection))
  end
end
