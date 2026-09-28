# edge_admin/test/edge_admin/ingress_tunneling/desired_state_test.exs
defmodule EdgeAdmin.IngressTunneling.DesiredStateTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.IngressTunneling.DesiredState
  alias EdgeAdmin.IngressTunneling.Resources.TunnelClientResources
  alias EdgeAdmin.IngressTunneling.Resources.TunnelConnectionResources
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Test.Fixtures

  test "builds an empty desired state for an Ingress without Tunnel Connections" do
    cluster = Fixtures.insert_cluster!(%{name: Fixtures.unique_name("ingress-state")})
    ingress = Fixtures.insert_node!(cluster.id)

    assert {:ok, desired_state} = DesiredState.build(ingress.id)

    assert desired_state["ingress_public_key"] == ingress.ingress_public_key
    assert desired_state["ingress_ipv4_address"] == nil
    assert desired_state["ingress_ipv6_address"] == nil
    assert desired_state["vpn_dns_suffix"] == Cluster.vpn_domain(cluster)
    assert desired_state["vpn_ipv4_range"] == cluster.ipv4_range
    assert desired_state["vpn_ipv6_range"] == cluster.ipv6_range
    assert desired_state["peers"] == []
  end

  test "builds each authorized Tunnel peer into the complete desired state" do
    cluster = Fixtures.insert_cluster!(%{name: Fixtures.unique_name("ingress-state")})
    ingress = Fixtures.insert_node!(cluster.id)
    {:ok, tunnel_client} = TunnelClientResources.create_generated()

    assert {:ok, connection} = TunnelConnectionResources.create_for_ingress(tunnel_client.id, ingress.id)
    assert {:ok, desired_state} = DesiredState.build(ingress.id)

    assert desired_state["ingress_ipv4_address"] == connection.ingress_ipv4_address
    assert desired_state["ingress_ipv6_address"] == connection.ingress_ipv6_address

    assert desired_state["peers"] == [
             %{
               "tunnel_connection_id" => connection.id,
               "tunnel_public_key" => tunnel_client.public_key,
               "tunnel_ipv4_address" => connection.tunnel_ipv4_address,
               "tunnel_ipv6_address" => connection.tunnel_ipv6_address,
               "allowed_ips" => [connection.tunnel_ipv4_address, connection.tunnel_ipv6_address]
             }
           ]
  end

  test "returns not found for an unknown Node" do
    assert {:error, :not_found} = DesiredState.build(Ecto.UUID.generate())
  end
end
