# edge_admin/test/edge_admin/ingress_tunneling/views/tunnel_client_view_test.exs
defmodule EdgeAdmin.IngressTunneling.Views.TunnelClientViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.IngressTunneling.Views.TunnelClientView

  @public_key Base.encode64(:binary.copy(<<1>>, 32))
  @private_key Base.encode64(:binary.copy(<<2>>, 32))
  @inserted_at ~U[2026-09-17 02:36:00Z]

  defp tunnel_client do
    %TunnelClient{
      id: "0190f1e0-7b2a-7abc-8def-0123456789ab",
      public_key: @public_key,
      private_key: @private_key,
      inserted_at: @inserted_at,
      updated_at: @inserted_at
    }
  end

  test "renders the public identity without the private key" do
    rendered = TunnelClientView.render(tunnel_client())

    assert rendered.public_key == @public_key
    assert rendered.tunnel_connections == []
    refute Map.has_key?(rendered, :private_key)
  end

  test "renders connections without repeating the parent tunnel client id" do
    connection = %TunnelConnection{
      id: "0190f1e0-7b2a-7abc-8def-0123456789ac",
      tunnel_client_id: tunnel_client().id,
      node_id: "0190f1e0-7b2a-7abc-8def-0123456789ad",
      ingress_ipv4_address: "10.240.0.1/32",
      ingress_ipv6_address: "fd20:240::1/128",
      tunnel_ipv4_address: "10.240.0.2/32",
      tunnel_ipv6_address: "fd20:240::2/128",
      inserted_at: @inserted_at,
      updated_at: @inserted_at
    }

    client = tunnel_client()
    rendered = TunnelClientView.render(%{client | tunnel_connections: [connection]})
    assert [%{node_id: connection_node_id} = rendered_connection] = rendered.tunnel_connections
    assert connection_node_id == connection.node_id
    refute Map.has_key?(rendered_connection, :tunnel_client_id)
  end
end
