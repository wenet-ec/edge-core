# edge_admin/test/edge_admin/nodes/discovery_nodes_test.exs
defmodule EdgeAdmin.Nodes.DiscoveryNodesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp insert_cluster!(name) do
    sequence = System.unique_integer([:positive, :monotonic])

    Repo.insert!(%Cluster{
      id: Ecto.UUID.generate(),
      name: name,
      ipv4_range: "100.64.#{rem(sequence, 200)}.0/24",
      ipv6_range: "fd7a:91c2:4e8b:#{rem(sequence, 65_536)}::/64"
    })
  end

  defp insert_node!(cluster, attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      cluster_id: cluster.id,
      netmaker_host_id: Ecto.UUID.generate(),
      status: :healthy,
      last_seen_at: ~U[2026-02-01 12:00:00Z],
      version: "edge-1.2.3",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9586,
      http_proxy_port: 8080,
      socks5_proxy_port: 1080,
      api_token: Ecto.UUID.generate(),
      proxy_password: Ecto.UUID.generate(),
      self_update_enabled: true,
      inserted_at: ~U[2026-02-01 12:00:00Z],
      updated_at: ~U[2026-02-02 12:00:00Z]
    }

    Repo.insert!(struct(Node, Map.merge(defaults, attrs)))
  end

  test "includes every status without applying a default pagination limit" do
    cluster = insert_cluster!("discovery-statuses")

    nodes =
      Enum.map(1..51, fn index ->
        status = Enum.at([:healthy, :unhealthy, :unreachable], rem(index, 3))
        insert_node!(cluster, %{status: status})
      end)

    assert {:ok, discovered_nodes} = Nodes.list_nodes_for_discovery(%{})

    assert MapSet.new(Enum.map(discovered_nodes, & &1.id)) ==
             MapSet.new(Enum.map(nodes, & &1.id))

    assert MapSet.new(Enum.map(discovered_nodes, & &1.status)) ==
             MapSet.new([:healthy, :unhealthy, :unreachable])
  end

  test "applies the complete list-node filter contract without pagination" do
    prod = insert_cluster!("prod-east")
    staging = insert_cluster!("staging")

    target = insert_node!(prod, %{status: :unreachable})

    _non_matching =
      insert_node!(staging, %{
        status: :healthy,
        version: "edge-2.0.0",
        self_update_enabled: false,
        last_seen_at: ~U[2025-01-01 12:00:00Z],
        inserted_at: ~U[2025-01-01 12:00:00Z],
        updated_at: ~U[2025-01-02 12:00:00Z]
      })

    params = %{
      "node_id__in" => target.id,
      "status__in" => "unreachable",
      "version" => "edge-1.*",
      "self_update_enabled" => true,
      "cluster_name" => "prod*",
      "cluster_name__in" => "prod-east",
      "last_seen_at__gte" => "2026-02-01T00:00:00Z",
      "last_seen_at__lte" => "2026-02-02T00:00:00Z",
      "inserted_at__gte" => "2026-02-01T00:00:00Z",
      "inserted_at__lte" => "2026-02-02T00:00:00Z",
      "updated_at__gte" => "2026-02-02T00:00:00Z",
      "updated_at__lte" => "2026-02-03T00:00:00Z"
    }

    assert {:ok, [node]} = Nodes.list_nodes_for_discovery(params)
    assert node.id == target.id
  end
end
