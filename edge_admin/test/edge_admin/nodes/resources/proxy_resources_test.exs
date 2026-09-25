# edge_admin/test/edge_admin/nodes/resources/proxy_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.ProxyResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.ProxyResources
  alias EdgeAdmin.Test.Fixtures

  defp insert_cluster!(name, attrs \\ %{}) do
    Fixtures.insert_cluster!(Map.merge(%{name: name}, attrs))
  end

  defp insert_node!(cluster) do
    Fixtures.insert_node!(cluster.id, %{version: "edge-1.0.0"})
  end

  test "maps active node IDs and aliases to their proxy routing data" do
    cluster = insert_cluster!("proxy-active")
    node = insert_node!(cluster)

    alias_name = "edge-api"

    Fixtures.insert_alias!(node.id, cluster.id, %{name: alias_name})

    assert {:ok, identifiers} = ProxyResources.get_chain_identifiers(cluster.name)
    assert identifiers[node.id] == identifiers[alias_name]

    assert identifiers[node.id].id == node.id
    assert identifiers[node.id].proxy_password == node.proxy_password
    assert identifiers[node.id].http_proxy_port == node.http_proxy_port
    assert identifiers[node.id].socks5_proxy_port == node.socks5_proxy_port
    assert identifiers[node.id].cluster.name == cluster.name
  end

  test "returns an empty map for an active cluster without nodes and not found for missing or retired clusters" do
    empty_cluster = insert_cluster!("proxy-empty")
    retired_cluster = insert_cluster!("proxy-retired", %{deleted_at: ~U[2026-01-01 00:00:00Z]})
    _retired_node = insert_node!(retired_cluster)

    assert {:ok, %{}} = ProxyResources.get_chain_identifiers(empty_cluster.name)
    assert {:error, :not_found} = ProxyResources.get_chain_identifiers("proxy-missing")
    assert {:error, :not_found} = ProxyResources.get_chain_identifiers(retired_cluster.name)
  end
end
