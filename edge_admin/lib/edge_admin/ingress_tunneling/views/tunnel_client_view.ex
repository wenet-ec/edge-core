# edge_admin/lib/edge_admin/ingress_tunneling/views/tunnel_client_view.ex
defmodule EdgeAdmin.IngressTunneling.Views.TunnelClientView do
  @moduledoc """
  Canonical public render shape for Tunnel Clients.

  The private key is deliberately excluded from every public response.
  """

  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.View

  @spec render(TunnelClient.t()) :: map()
  def render(%TunnelClient{} = tunnel_client) do
    response = %{
      id: tunnel_client.id,
      public_key: tunnel_client.public_key,
      inserted_at: tunnel_client.inserted_at,
      updated_at: tunnel_client.updated_at
    }

    Map.put(
      response,
      :tunnel_connections,
      View.render_embedded(tunnel_client.tunnel_connections, &render_embedded_tunnel_connection/1)
    )
  end

  defp render_embedded_tunnel_connection(%TunnelConnection{} = connection),
    do: %{
      id: connection.id,
      node_id: connection.node_id,
      ingress_ipv4_address: connection.ingress_ipv4_address,
      ingress_ipv6_address: connection.ingress_ipv6_address,
      tunnel_ipv4_address: connection.tunnel_ipv4_address,
      tunnel_ipv6_address: connection.tunnel_ipv6_address,
      inserted_at: connection.inserted_at,
      updated_at: connection.updated_at
    }
end
