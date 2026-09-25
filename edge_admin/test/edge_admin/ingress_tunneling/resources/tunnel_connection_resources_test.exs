# edge_admin/test/edge_admin/ingress_tunneling/resources/tunnel_connection_resources_test.exs
defmodule EdgeAdmin.IngressTunneling.Resources.TunnelConnectionResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.IngressTunneling.Resources.TunnelClientResources
  alias EdgeAdmin.IngressTunneling.Resources.TunnelConnectionResources
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Test.Fixtures

  defp insert_cluster do
    Fixtures.insert_cluster!(%{name: Fixtures.unique_name("ingress-tunnel")})
  end

  defp insert_ingress(cluster_id) do
    Fixtures.insert_node!(cluster_id, %{
      version: "1.0.0",
      host_metrics_port: 49_100,
      wireguard_metrics_port: 49_586,
      http_proxy_port: 43_128,
      socks5_proxy_port: 41_080
    })
  end

  test "allocates distinct addresses for connections on one Ingress" do
    ingress = then(insert_cluster(), &insert_ingress(&1.id))
    {:ok, first_tunnel_client} = TunnelClientResources.create_generated()
    {:ok, second_tunnel_client} = TunnelClientResources.create_generated()

    assert {:ok, first_connection} =
             TunnelConnectionResources.create_for_ingress(first_tunnel_client.id, ingress.id)

    assert {:ok, second_connection} =
             TunnelConnectionResources.create_for_ingress(second_tunnel_client.id, ingress.id)

    assert first_connection.ingress_ipv4_address == "10.240.0.1/32"
    assert second_connection.ingress_ipv4_address == "10.240.0.1/32"
    assert first_connection.ingress_ipv6_address == "fd20:240::1/128"
    assert second_connection.ingress_ipv6_address == "fd20:240::1/128"
    assert first_connection.tunnel_ipv4_address == "10.240.0.2/32"
    assert second_connection.tunnel_ipv4_address == "10.240.0.3/32"
    assert first_connection.tunnel_ipv6_address == "fd20:240::2/128"
    assert second_connection.tunnel_ipv6_address == "fd20:240::3/128"
  end

  test "reuses the same addresses for separate Ingress realms" do
    cluster = insert_cluster()
    first_ingress = insert_ingress(cluster.id)
    second_ingress = insert_ingress(cluster.id)
    {:ok, first_tunnel_client} = TunnelClientResources.create_generated()
    {:ok, second_tunnel_client} = TunnelClientResources.create_generated()

    assert {:ok, first_connection} =
             TunnelConnectionResources.create_for_ingress(first_tunnel_client.id, first_ingress.id)

    assert {:ok, second_connection} =
             TunnelConnectionResources.create_for_ingress(second_tunnel_client.id, second_ingress.id)

    assert {
             first_connection.ingress_ipv4_address,
             first_connection.ingress_ipv6_address,
             first_connection.tunnel_ipv4_address,
             first_connection.tunnel_ipv6_address
           } ==
             {
               second_connection.ingress_ipv4_address,
               second_connection.ingress_ipv6_address,
               second_connection.tunnel_ipv4_address,
               second_connection.tunnel_ipv6_address
             }
  end

  test "rejects a duplicate Tunnel Client and Ingress pairing" do
    ingress = then(insert_cluster(), &insert_ingress(&1.id))
    {:ok, tunnel_client} = TunnelClientResources.create_generated()

    assert {:ok, _connection} =
             TunnelConnectionResources.create_for_ingress(tunnel_client.id, ingress.id)

    assert {:error, {:conflict, reason}} =
             TunnelConnectionResources.create_for_ingress(tunnel_client.id, ingress.id)

    assert reason =~ "tunnel_client_id has already been taken"
  end

  test "returns not found when the Tunnel Client or Ingress does not exist" do
    ingress = then(insert_cluster(), &insert_ingress(&1.id))
    {:ok, tunnel_client} = TunnelClientResources.create_generated()

    assert {:error, :not_found} =
             TunnelConnectionResources.create_for_ingress(Ecto.UUID.generate(), ingress.id)

    assert {:error, :not_found} =
             TunnelConnectionResources.create_for_ingress(tunnel_client.id, Ecto.UUID.generate())
  end

  test "deleting a Tunnel Client returns affected Ingress IDs and cascades its connections" do
    ingress = then(insert_cluster(), &insert_ingress(&1.id))
    {:ok, tunnel_client} = TunnelClientResources.create_generated()
    {:ok, connection} = TunnelConnectionResources.create_for_ingress(tunnel_client.id, ingress.id)

    assert {:ok, {deleted_client, [ingress_id]}} =
             TunnelClientResources.delete_with_connections(tunnel_client)

    assert deleted_client.id == tunnel_client.id
    assert ingress_id == ingress.id
    assert Repo.get(EdgeAdmin.IngressTunneling.Schemas.TunnelConnection, connection.id) == nil
  end
end
