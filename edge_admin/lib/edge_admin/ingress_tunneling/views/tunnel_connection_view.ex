# edge_admin/lib/edge_admin/ingress_tunneling/views/tunnel_connection_view.ex
defmodule EdgeAdmin.IngressTunneling.Views.TunnelConnectionView do
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection

  @spec render(TunnelConnection.t()) :: map()
  def render(%TunnelConnection{} = connection) do
    %{
      id: connection.id,
      tunnel_client_id: connection.tunnel_client_id,
      node_id: connection.node_id,
      ingress_ipv4_address: connection.ingress_ipv4_address,
      ingress_ipv6_address: connection.ingress_ipv6_address,
      tunnel_ipv4_address: connection.tunnel_ipv4_address,
      tunnel_ipv6_address: connection.tunnel_ipv6_address,
      inserted_at: connection.inserted_at,
      updated_at: connection.updated_at
    }
  end
end
