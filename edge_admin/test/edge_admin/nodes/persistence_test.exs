# edge_admin/test/edge_admin/nodes/persistence_test.exs
defmodule EdgeAdmin.Nodes.PersistenceTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Persistence
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node

  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])

  defp insert_cluster(overrides \\ %{}) do
    id = unique_id()

    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          name: "cluster-#{id}",
          ipv4_range: "100.101.#{rem(id, 256)}.0/24",
          ipv6_range: "fd7a:91c2:4e8b:#{rem(id, 65_536)}::/64"
        },
        overrides
      )

    Repo.insert!(struct(Cluster, attrs))
  end

  defp insert_node(cluster_id) do
    Repo.insert!(%Node{
      id: Ecto.UUID.generate(),
      cluster_id: cluster_id,
      netmaker_host_id: Ecto.UUID.generate(),
      status: :healthy,
      version: "0.1.0",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9_100,
      wireguard_metrics_port: 9_586,
      http_proxy_port: 8_080,
      socks5_proxy_port: 1_080,
      api_token: Ecto.UUID.generate(),
      proxy_password: Ecto.UUID.generate()
    })
  end

  describe "lock_active_cluster/1" do
    test "returns an active cluster by name" do
      cluster = insert_cluster()

      assert Persistence.lock_active_cluster(cluster.name).id == cluster.id
    end

    test "does not return retired or missing clusters" do
      retired = insert_cluster(%{deleted_at: ~U[2026-01-01 00:00:00Z]})

      assert Persistence.lock_active_cluster(retired.name) == nil
      assert Persistence.lock_active_cluster("missing-cluster") == nil
    end
  end

  describe "lock_node/1" do
    test "returns a node by ID" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)

      assert Persistence.lock_node(node.id).id == node.id
    end

    test "returns nil for a missing node" do
      assert Persistence.lock_node(Ecto.UUID.generate()) == nil
    end
  end
end
