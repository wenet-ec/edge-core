# edge_admin/test/edge_admin/nodes/resources/cluster_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.ClusterResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.ClusterResources
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp insert_cluster!(name, attrs \\ %{}) do
    sequence = System.unique_integer([:positive, :monotonic])

    defaults = %{
      id: Ecto.UUID.generate(),
      name: name,
      ipv4_range: "100.64.#{rem(sequence, 200)}.0/24",
      ipv6_range: "fd7a:91c2:4e8b:#{rem(sequence, 65_536)}::/64"
    }

    Repo.insert!(struct(Cluster, Map.merge(defaults, attrs)))
  end

  defp insert_node!(cluster, status) do
    sequence = System.unique_integer([:positive, :monotonic])
    public_key = Base.encode64(<<rem(sequence, 256), :binary.copy(<<0>>, 31)::binary>>)

    Repo.insert!(%Node{
      id: Ecto.UUID.generate(),
      cluster_id: cluster.id,
      vpn_host_id: Ecto.UUID.generate(),
      status: status,
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

  test "lists active cluster-to-node mappings with status and prefix options" do
    mixed = insert_cluster!("mapping-mixed")
    insert_cluster!("mapping-empty")
    unhealthy_only = insert_cluster!("mapping-unhealthy")
    retired = insert_cluster!("mapping-retired", %{deleted_at: ~U[2026-01-01 00:00:00Z]})

    healthy_node = insert_node!(mixed, :healthy)
    _unhealthy_node = insert_node!(mixed, :unhealthy)
    _unhealthy_only_node = insert_node!(unhealthy_only, :unhealthy)
    _retired_node = insert_node!(retired, :healthy)

    mappings = ClusterResources.list_node_mappings(filter_status: [:healthy], prefix: true)
    mappings_by_name = Map.new(mappings, &{&1.name, &1.nodes})
    mapping_names = Enum.sort(Map.keys(mappings_by_name))

    assert mapping_names == ["cluster-mapping-empty", "cluster-mapping-mixed"]

    assert mappings_by_name["cluster-mapping-mixed"] == [Node.node_name(healthy_node)]
    assert mappings_by_name["cluster-mapping-empty"] == []
  end
end
