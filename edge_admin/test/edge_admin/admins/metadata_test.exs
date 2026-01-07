defmodule EdgeAdmin.Admins.MetadataTest do
  use ExUnit.Case, async: false

  alias EdgeAdmin.Admins.Metadata

  # Note: async: false because we're using a named ETS table

  setup do
    # Create ETS table manually for testing
    # In production, this is created by Metadata.init/1
    table = :metadata

    # Clean up any existing table
    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    :ets.new(table, [:set, :public, :named_table, read_concurrency: true])

    # Populate with test data
    :ets.insert(table, {
      :admin,
      %{
        id: "test-admin-id",
        name: "admin-test",
        max_capacity: 100,
        erlang_node_name: :"admin@test.local",
        dns_hostname: "admin-test.cluster-main.nm.internal",
        admin_cluster_name: "admin-cluster-main",
        netmaker_host_id: "host-123",
        last_computed_at: ~U[2025-01-07 12:00:00Z]
      }
    })

    :ets.insert(table, {
      :admin_cluster,
      %{
        name: "admin-cluster-main",
        total_admins: 2,
        degraded: false,
        topology: [
          %{
            name: "admin-test",
            max_capacity: 100,
            dns_hostname: "admin-test.cluster-main.nm.internal",
            erlang_node_name: :"admin@test.local",
            netmaker_host_id: "host-123"
          },
          %{
            name: "admin-peer",
            max_capacity: 200,
            dns_hostname: "admin-peer.cluster-main.nm.internal",
            erlang_node_name: :"admin@peer.local",
            netmaker_host_id: "host-456"
          }
        ]
      }
    })

    :ets.insert(table, {
      :edge_clusters,
      %{
        "admin-test" => %{
          "cluster-prod" => ["node-1", "node-2", "node-3"],
          "cluster-dev" => ["node-4"]
        },
        "admin-peer" => %{
          "cluster-staging" => ["node-5", "node-6"]
        }
      }
    })

    :ets.insert(table, {
      :orphaned_clusters,
      %{
        "cluster-orphaned" => ["node-7", "node-8"]
      }
    })

    on_exit(fn ->
      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end
    end)

    :ok
  end

  describe "get_admin/0" do
    test "returns this admin's info from ETS" do
      admin = Metadata.get_admin()

      assert admin.id == "test-admin-id"
      assert admin.name == "admin-test"
      assert admin.max_capacity == 100
      assert admin.dns_hostname == "admin-test.cluster-main.nm.internal"
      assert admin.netmaker_host_id == "host-123"
    end
  end

  describe "get_admin_cluster/0" do
    test "returns admin cluster topology" do
      cluster = Metadata.get_admin_cluster()

      assert cluster.name == "admin-cluster-main"
      assert cluster.total_admins == 2
      assert cluster.degraded == false
      assert length(cluster.topology) == 2
    end

    test "topology contains all admins with details" do
      cluster = Metadata.get_admin_cluster()

      admin_names = Enum.map(cluster.topology, & &1.name)
      assert "admin-test" in admin_names
      assert "admin-peer" in admin_names

      admin_test = Enum.find(cluster.topology, &(&1.name == "admin-test"))
      assert admin_test.max_capacity == 100
      assert admin_test.netmaker_host_id == "host-123"
    end
  end

  describe "get_my_clusters/0" do
    test "returns clusters assigned to this admin" do
      my_clusters = Metadata.get_my_clusters()

      assert map_size(my_clusters) == 2
      assert my_clusters["cluster-prod"] == ["node-1", "node-2", "node-3"]
      assert my_clusters["cluster-dev"] == ["node-4"]
    end

    test "does not include peer admin's clusters" do
      my_clusters = Metadata.get_my_clusters()

      refute Map.has_key?(my_clusters, "cluster-staging")
    end
  end

  describe "get_cluster_owner/1" do
    test "returns admin name that owns the cluster" do
      assert Metadata.get_cluster_owner("cluster-prod") == "admin-test"
      assert Metadata.get_cluster_owner("cluster-dev") == "admin-test"
      assert Metadata.get_cluster_owner("cluster-staging") == "admin-peer"
    end

    test "returns nil for non-existent cluster" do
      assert Metadata.get_cluster_owner("cluster-nonexistent") == nil
    end

    test "returns nil for orphaned cluster" do
      # Orphaned clusters don't have owners
      assert Metadata.get_cluster_owner("cluster-orphaned") == nil
    end
  end

  describe "find_node_cluster/1" do
    test "finds cluster for node assigned to this admin" do
      assert {:ok, "cluster-prod", "admin-test"} = Metadata.find_node_cluster("node-1")
      assert {:ok, "cluster-prod", "admin-test"} = Metadata.find_node_cluster("node-2")
      assert {:ok, "cluster-dev", "admin-test"} = Metadata.find_node_cluster("node-4")
    end

    test "finds cluster for node assigned to peer admin" do
      assert {:ok, "cluster-staging", "admin-peer"} = Metadata.find_node_cluster("node-5")
      assert {:ok, "cluster-staging", "admin-peer"} = Metadata.find_node_cluster("node-6")
    end

    test "returns error for non-existent node" do
      assert {:error, :not_found} = Metadata.find_node_cluster("node-999")
    end

    test "returns error for orphaned node" do
      # Orphaned nodes are in orphaned_clusters, not edge_clusters
      assert {:error, :not_found} = Metadata.find_node_cluster("node-7")
    end

    test "handles empty cluster with no nodes" do
      # Add empty cluster to ETS
      :ets.insert(:metadata, {
        :edge_clusters,
        %{
          "admin-test" => %{
            "cluster-prod" => ["node-1", "node-2", "node-3"],
            "cluster-dev" => ["node-4"],
            "cluster-empty" => []
          },
          "admin-peer" => %{
            "cluster-staging" => ["node-5", "node-6"]
          }
        }
      })

      # Node not in empty cluster
      assert {:error, :not_found} = Metadata.find_node_cluster("node-empty")
    end
  end

  describe "get_peer_admins/0" do
    test "returns full topology including this admin and peers" do
      peers = Metadata.get_peer_admins()

      assert length(peers) == 2

      admin_names = Enum.map(peers, & &1.name)
      assert "admin-test" in admin_names
      assert "admin-peer" in admin_names
    end

    test "peer admins include all required fields" do
      peers = Metadata.get_peer_admins()

      admin_peer = Enum.find(peers, &(&1.name == "admin-peer"))
      assert admin_peer.max_capacity == 200
      assert admin_peer.dns_hostname == "admin-peer.cluster-main.nm.internal"
      assert admin_peer.netmaker_host_id == "host-456"
    end
  end

  describe "get_edge_clusters/0" do
    test "returns all cluster assignments for all admins" do
      assignments = Metadata.get_edge_clusters()

      assert map_size(assignments) == 2
      assert map_size(assignments["admin-test"]) == 2
      assert map_size(assignments["admin-peer"]) == 1
    end

    test "includes node lists for each cluster" do
      assignments = Metadata.get_edge_clusters()

      assert assignments["admin-test"]["cluster-prod"] == ["node-1", "node-2", "node-3"]
      assert assignments["admin-peer"]["cluster-staging"] == ["node-5", "node-6"]
    end
  end

  describe "get_orphaned_clusters/0" do
    test "returns orphaned clusters with their nodes" do
      orphaned = Metadata.get_orphaned_clusters()

      assert map_size(orphaned) == 1
      assert orphaned["cluster-orphaned"] == ["node-7", "node-8"]
    end

    test "returns empty map when no orphaned clusters" do
      # Update ETS to have no orphaned clusters
      :ets.insert(:metadata, {
        :orphaned_clusters,
        %{}
      })

      orphaned = Metadata.get_orphaned_clusters()
      assert orphaned == %{}
    end
  end

  describe "degraded?/0" do
    test "returns false when admin cluster is healthy" do
      assert Metadata.degraded?() == false
    end

    test "returns true when admin cluster is degraded" do
      # Update ETS to simulate degraded state
      :ets.insert(:metadata, {
        :admin_cluster,
        %{
          name: "admin-cluster-main",
          total_admins: 1,
          degraded: true,
          topology: [
            %{name: "admin-test", max_capacity: 100}
          ]
        }
      })

      assert Metadata.degraded?() == true
    end
  end

  describe "edge cases" do
    test "handles admin with no assigned clusters" do
      :ets.insert(:metadata, {
        :edge_clusters,
        %{
          "admin-test" => %{},
          "admin-peer" => %{
            "cluster-staging" => ["node-5"]
          }
        }
      })

      my_clusters = Metadata.get_my_clusters()
      assert my_clusters == %{}
    end

    test "handles single admin topology" do
      :ets.insert(:metadata, {
        :admin_cluster,
        %{
          name: "admin-cluster-main",
          total_admins: 1,
          degraded: false,
          topology: [
            %{name: "admin-test", max_capacity: 100}
          ]
        }
      })

      cluster = Metadata.get_admin_cluster()
      assert cluster.total_admins == 1
      assert length(cluster.topology) == 1
    end

    test "handles cluster with single node" do
      :ets.insert(:metadata, {
        :edge_clusters,
        %{
          "admin-test" => %{
            "cluster-single" => ["only-node"]
          }
        }
      })

      assert {:ok, "cluster-single", "admin-test"} =
               Metadata.find_node_cluster("only-node")
    end

    test "handles cluster with many nodes" do
      many_nodes = Enum.map(1..100, &"node-#{&1}")

      :ets.insert(:metadata, {
        :edge_clusters,
        %{
          "admin-test" => %{
            "cluster-large" => many_nodes
          }
        }
      })

      assert {:ok, "cluster-large", "admin-test"} = Metadata.find_node_cluster("node-50")
      assert {:ok, "cluster-large", "admin-test"} = Metadata.find_node_cluster("node-100")
    end
  end
end
