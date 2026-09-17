# edge_admin/test/edge_admin/ingress_tunneling/resources/tunnel_clients_test.exs
defmodule EdgeAdmin.IngressTunneling.Resources.TunnelClientsTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.IngressTunneling.Resources.TunnelClients
  alias EdgeAdmin.Repo

  test "creates and persists an Admin-generated Tunnel Client" do
    assert {:ok, tunnel_client} = TunnelClients.create()
    assert is_binary(tunnel_client.public_key)
    assert is_binary(tunnel_client.private_key)
  end

  test "lists, gets, and deletes Tunnel Clients" do
    assert {:ok, tunnel_client} = TunnelClients.create()
    assert {:ok, {[listed_client], _meta}} = TunnelClients.list()
    assert listed_client.id == tunnel_client.id
    assert {:ok, fetched_client} = TunnelClients.get(tunnel_client.id)
    assert fetched_client.id == tunnel_client.id
    assert {:ok, deleted_client} = TunnelClients.delete(tunnel_client)
    assert deleted_client.id == tunnel_client.id
    assert Repo.get(EdgeAdmin.IngressTunneling.Schemas.TunnelClient, tunnel_client.id) == nil
  end

  test "returns not found for an invalid or absent Tunnel Client ID" do
    assert {:error, :not_found} = TunnelClients.get("not-a-uuid")
    assert {:error, :not_found} = TunnelClients.get(Ecto.UUID.generate())
  end
end
