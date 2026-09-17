# edge_admin/lib/edge_admin_web/controllers/ingress_tunneling/tunnel_client_json.ex
defmodule EdgeAdminWeb.Controllers.IngressTunneling.TunnelClientJSON do
  alias EdgeAdmin.IngressTunneling.Views.TunnelClientView
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, tunnel_clients: tunnel_clients, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(tunnel_clients, &TunnelClientView.render/1), flop_meta)
  end

  def show(%{conn: conn, tunnel_client: tunnel_client}) do
    ResponseEnvelope.success(conn, TunnelClientView.render(tunnel_client))
  end
end
