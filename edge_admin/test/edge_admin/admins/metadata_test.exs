# edge_admin/test/edge_admin/admins/metadata_test.exs
defmodule EdgeAdmin.Admins.MetadataTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Admins.Metadata

  describe "ETS initialization" do
    test "creates ETS table with initial state" do
      # ETS table should exist
      assert :ets.info(:metadata) != :undefined

      # Check :admin key
      [{:admin, admin}] = :ets.lookup(:metadata, :admin)
      assert admin.id != nil
      assert admin.max_capacity > 0
      assert admin.erlang_node_name == Node.self()
      assert admin.dns_hostname != nil
      assert admin.admin_cluster_name != nil

      # Check :admin_cluster key
      [{:admin_cluster, admin_cluster}] = :ets.lookup(:metadata, :admin_cluster)
      assert admin_cluster.name != nil
      assert admin_cluster.degraded == false

      # Check :edge_clusters key (uses admin_name as key)
      [{:edge_clusters, edge_clusters}] = :ets.lookup(:metadata, :edge_clusters)
      assert is_map(edge_clusters)
      assert Map.has_key?(edge_clusters, admin.name)

      # Check :orphaned_clusters key
      [{:orphaned_clusters, orphaned_clusters}] = :ets.lookup(:metadata, :orphaned_clusters)
      assert is_map(orphaned_clusters)
      assert orphaned_clusters == %{}
    end
  end

  describe "get_admin_id/0" do
    test "returns current admin ID" do
      admin_id = Metadata.get_admin_id()
      assert is_binary(admin_id)
      assert String.starts_with?(admin_id, "admin-") == false
      # admin_id is just the random part, not prefixed
    end
  end

  describe "get_admin/0" do
    test "returns full admin info" do
      admin = Metadata.get_admin()
      assert admin.id != nil
      assert admin.max_capacity > 0
      assert admin.erlang_node_name == Node.self()
    end
  end

  describe "get_cluster_owner/1" do
    test "returns nil for non-existent cluster" do
      assert Metadata.get_cluster_owner("non-existent") == nil
    end

    test "returns admin_name for assigned cluster" do
      # Insert test data into ETS
      admin = Metadata.get_admin()

      :ets.insert(:metadata, {
        :edge_clusters,
        %{
          admin.name => %{
            "cluster-test" => ["node-1", "node-2"]
          }
        }
      })

      assert Metadata.get_cluster_owner("cluster-test") == admin.name
    end
  end

  describe "get_my_clusters/0" do
    test "returns clusters managed by this admin" do
      admin = Metadata.get_admin()

      :ets.insert(:metadata, {
        :edge_clusters,
        %{
          admin.name => %{
            "cluster-a" => ["node-1"],
            "cluster-b" => []
          }
        }
      })

      clusters = Metadata.get_my_clusters()
      assert clusters == %{"cluster-a" => ["node-1"], "cluster-b" => []}
    end
  end

  describe "get_peer_admins/0" do
    test "returns peer admin topology" do
      :ets.insert(:metadata, {
        :admin_cluster,
        %{
          name: "admin-cluster-1",
          total_admins: 2,
          degraded: false,
          topology: [
            %{name: "admin-1", max_capacity: 200},
            %{name: "admin-2", max_capacity: 300}
          ]
        }
      })

      peers = Metadata.get_peer_admins()
      assert length(peers) == 2
      assert Enum.any?(peers, fn p -> p.name == "admin-1" end)
      assert Enum.any?(peers, fn p -> p.name == "admin-2" end)
    end
  end

  describe "get_orphaned_clusters/0" do
    test "returns empty map when no orphaned clusters" do
      :ets.insert(:metadata, {:orphaned_clusters, %{}})

      assert Metadata.get_orphaned_clusters() == %{}
    end

    test "returns orphaned clusters when system is degraded" do
      orphaned = %{
        "cluster-orphaned-1" => ["node-1", "node-2"],
        "cluster-orphaned-2" => ["node-3"]
      }

      :ets.insert(:metadata, {:orphaned_clusters, orphaned})

      assert Metadata.get_orphaned_clusters() == orphaned
    end
  end

  describe "degraded?/0" do
    test "returns false when not degraded" do
      :ets.insert(:metadata, {
        :admin_cluster,
        %{
          name: "admin-cluster-1",
          total_admins: 1,
          degraded: false,
          topology: []
        }
      })

      refute Metadata.degraded?()
    end

    test "returns true when degraded" do
      :ets.insert(:metadata, {
        :admin_cluster,
        %{
          name: "admin-cluster-1",
          total_admins: 1,
          degraded: true,
          topology: []
        }
      })

      assert Metadata.degraded?()
    end
  end

  describe "initialized?/0" do
    test "returns true after initialization" do
      assert Metadata.initialized?()
    end
  end

  describe "recompute_now/0" do
    test "triggers recomputation and returns :ok" do
      assert Metadata.recompute_now() == :ok
    end
  end
end
