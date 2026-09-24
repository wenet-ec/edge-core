# edge_admin/test/edge_admin/ingress_tunneling/resources/tunnel_client_resources_test.exs
defmodule EdgeAdmin.IngressTunneling.Resources.TunnelClientResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.IngressTunneling.Resources.TunnelClientResources
  alias EdgeAdmin.IngressTunneling.WireGuard
  alias EdgeAdmin.Repo

  test "create/1 persists supplied key attributes" do
    attrs = WireGuard.generate_keypair()

    assert {:ok, tunnel_client} = TunnelClientResources.create(attrs)
    assert tunnel_client.public_key == attrs.public_key
    assert tunnel_client.private_key == attrs.private_key
  end

  test "creates and persists an Admin-generated Tunnel Client" do
    assert {:ok, tunnel_client} = TunnelClientResources.create_generated()
    assert is_binary(tunnel_client.public_key)
    assert is_binary(tunnel_client.private_key)
  end

  test "lists, gets, and deletes Tunnel Clients" do
    assert {:ok, tunnel_client} = TunnelClientResources.create_generated()
    assert {:ok, {[listed_client], _meta}} = TunnelClientResources.list()
    assert listed_client.id == tunnel_client.id
    assert {:ok, fetched_client} = TunnelClientResources.get(tunnel_client.id)
    assert fetched_client.id == tunnel_client.id
    assert {:ok, deleted_client} = TunnelClientResources.delete(tunnel_client)
    assert deleted_client.id == tunnel_client.id
    assert Repo.get(EdgeAdmin.IngressTunneling.Schemas.TunnelClient, tunnel_client.id) == nil
  end

  test "returns not found for an invalid or absent Tunnel Client ID" do
    assert {:error, :not_found} = TunnelClientResources.get("not-a-uuid")
    assert {:error, :not_found} = TunnelClientResources.get(Ecto.UUID.generate())
  end
end
