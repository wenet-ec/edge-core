defmodule EdgeAdminWeb.Live.MembershipDashboardTest do
  use ExUnit.Case, async: false

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdminWeb.Live.MembershipDashboard

  setup do
    assert :undefined == :ets.whereis(:metadata)
    :ets.new(:metadata, [:set, :public, :named_table])

    on_exit(fn ->
      if :ets.whereis(:metadata) != :undefined do
        :ets.delete(:metadata)
      end
    end)

    snapshot = %{
      admin: %{
        id: "admin-id",
        name: "admin-a",
        admin_cluster_name: "admin-cluster-a",
        last_computed_at: ~U[2026-07-17 09:30:00Z]
      },
      admin_cluster: %{
        name: "admin-cluster-a",
        topology: [%{name: "admin-a"}, %{name: "admin-b"}],
        weak_leader: "admin-a",
        total_admins: 2,
        total_nodes: 3,
        total_edge_capacity: 10,
        degraded: false
      },
      edge_clusters: %{"admin-a" => %{"cluster-a" => ["node-1"]}},
      orphaned_clusters: %{"cluster-b" => ["node-2", "node-3"]},
      node_index: %{"node-1" => {"cluster-a", "admin-a"}}
    }

    :ets.insert(:metadata, {:snapshot, snapshot})
    %{snapshot: snapshot}
  end

  test "metadata readers return fields from one published snapshot", %{snapshot: snapshot} do
    assert Metadata.snapshot() == snapshot
    assert Metadata.get_admin() == snapshot.admin
    assert Metadata.get_admin_cluster() == snapshot.admin_cluster
    assert Metadata.get_edge_clusters() == snapshot.edge_clusters
    assert Metadata.get_orphaned_clusters() == snapshot.orphaned_clusters
    assert Metadata.get_my_clusters() == snapshot.edge_clusters["admin-a"]
    assert Metadata.get_cluster_owner("cluster-a") == "admin-a"
    assert Metadata.find_node_cluster("node-1") == {:ok, "cluster-a", "admin-a"}
    assert Metadata.degraded?() == false
    assert Metadata.am_i_weak_leader?() == true
  end

  test "dashboard snapshot is internally consistent and includes lifecycle status", %{snapshot: snapshot} do
    assert {:ok, data} = MembershipDashboard.remote_snapshot()

    assert data.admin == snapshot.admin
    assert data.admin_cluster == snapshot.admin_cluster
    assert data.edge_clusters == snapshot.edge_clusters
    assert data.orphaned == snapshot.orphaned_clusters
    assert data.weak_leader?

    assert data.metadata_status == %{
             recomputing?: false,
             pending_recompute: false,
             last_recompute_error: nil
           }
  end
end
