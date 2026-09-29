# edge_admin/test/edge_admin/ingress_tunneling/desired_state_test.exs
defmodule EdgeAdmin.IngressTunneling.DesiredStateTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.IngressTunneling.DesiredState
  alias EdgeAdmin.IngressTunneling.Resources.TunnelClientResources
  alias EdgeAdmin.IngressTunneling.Resources.TunnelConnectionResources
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Test.Fixtures

  test "builds an empty desired state for an Ingress without Tunnel Connections" do
    cluster = Fixtures.insert_cluster!(%{name: Fixtures.unique_name("ingress-state")})
    ingress = Fixtures.insert_node!(cluster.id)

    assert {:ok, desired_state} = DesiredState.build(ingress.id)

    assert desired_state["ingress_public_key"] == ingress.ingress_public_key
    assert desired_state["ingress_ipv4_addresses"] == []
    assert desired_state["ingress_ipv6_addresses"] == []
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

    assert desired_state["ingress_ipv4_addresses"] == [connection.ingress_ipv4_address]
    assert desired_state["ingress_ipv6_addresses"] == [connection.ingress_ipv6_address]

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

  test "retains old Ingress addresses in the snapshot while connections still reference them" do
    cluster = Fixtures.insert_cluster!(%{name: Fixtures.unique_name("ingress-state")})
    ingress = Fixtures.insert_node!(cluster.id)
    {:ok, old_client} = TunnelClientResources.create_generated()

    {:ok, old_connection} =
      TunnelConnectionResources.create_for_ingress(old_client.id, ingress.id)

    old_ipv4_address = "10.240.0.3/32"
    old_ipv6_address = "fd20:240::3/128"

    old_connection
    |> TunnelConnection.changeset(%{
      ingress_ipv4_address: old_ipv4_address,
      ingress_ipv6_address: old_ipv6_address
    })
    |> Repo.update!()

    {:ok, new_client} = TunnelClientResources.create_generated()

    {:ok, new_connection} =
      TunnelConnectionResources.create_for_ingress(new_client.id, ingress.id)

    assert new_connection.tunnel_ipv4_address == "10.240.0.4/32"
    assert new_connection.tunnel_ipv6_address == "fd20:240::4/128"

    {:ok, another_client} = TunnelClientResources.create_generated()

    assert {:ok, another_connection} =
             TunnelConnectionResources.create_for_ingress(another_client.id, ingress.id)

    assert another_connection.ingress_ipv4_address == new_connection.ingress_ipv4_address
    assert another_connection.ingress_ipv6_address == new_connection.ingress_ipv6_address

    assert {:ok, ingress_tunneling} = DesiredState.build(ingress.id)

    assert ingress_tunneling["ingress_ipv4_addresses"] ==
             Enum.sort([old_ipv4_address, new_connection.ingress_ipv4_address])

    assert ingress_tunneling["ingress_ipv6_addresses"] ==
             Enum.sort([old_ipv6_address, new_connection.ingress_ipv6_address])
  end

  test "returns not found for an unknown Node" do
    assert {:error, :not_found} = DesiredState.build(Ecto.UUID.generate())
  end
end
