# edge_admin/test/edge_admin/nodes/resources/proxy_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.ProxyResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.ProxyResources
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp insert_cluster!(name, attrs \\ %{}) do
    sequence = System.unique_integer([:positive, :monotonic])

    Repo.insert!(%Cluster{
      id: Ecto.UUID.generate(),
      name: name,
      ipv4_range: "100.64.#{rem(sequence, 200)}.0/24",
      ipv6_range: "fd7a:91c2:4e8b:#{rem(sequence, 65_536)}::/64",
      deleted_at: Map.get(attrs, :deleted_at)
    })
  end

  defp insert_node!(cluster) do
    sequence = System.unique_integer([:positive, :monotonic])
    public_key = Base.encode64(<<rem(sequence, 256), :binary.copy(<<0>>, 31)::binary>>)

    Repo.insert!(%Node{
      id: Ecto.UUID.generate(),
      cluster_id: cluster.id,
      vpn_host_id: Ecto.UUID.generate(),
      version: "edge-1.0.0",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9586,
      http_proxy_port: 8080,
      socks5_proxy_port: 1080,
      api_token: Ecto.UUID.generate(),
      proxy_password: "proxy-#{sequence}",
      ingress_public_key: public_key
    })
  end

  test "maps active node IDs and aliases to their proxy routing data" do
    cluster = insert_cluster!("proxy-active")
    node = insert_node!(cluster)

    alias_name = "edge-api"

    Repo.insert!(%Alias{
      id: Ecto.UUID.generate(),
      name: alias_name,
      node_id: node.id,
      cluster_id: cluster.id
    })

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
