# edge_admin/test/edge_admin_web/controllers/admins/orphaned_clusters_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Admins.OrphanedClustersControllerTest do
  use EdgeAdminWeb.ConnCase, async: true

  setup %{conn: conn} do
    # Set up the ETS table with test metadata
    setup_metadata_ets()

    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp setup_metadata_ets do
    # Create table if it doesn't exist
    if :ets.whereis(:metadata) == :undefined do
      :ets.new(:metadata, [:set, :public, :named_table, read_concurrency: true])
    end

    # Insert test admin data
    :ets.insert(:metadata, {
      :admin,
      %{
        id: "admin-test123456",
        max_capacity: 100,
        erlang_node_name: :"admin@admin-test123456.admin-cluster-test.nm.internal",
        dns_hostname: "admin-test123456.admin-cluster-test.nm.internal",
        admin_cluster_name: "admin-cluster-test",
        last_computed_at: ~U[2025-01-15 12:00:00Z]
      }
    })

    # Insert test orphaned clusters data (initially empty - no degraded mode)
    :ets.insert(:metadata, {:orphaned_clusters, %{}})
  end

  describe "GET /api/admins/orphaned_clusters" do
    test "returns empty map when system is not degraded", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/orphaned_clusters")
      response = json_response(conn, 200)

      assert response == %{}
    end

    test "returns orphaned clusters when system is degraded", %{conn: conn} do
      # Simulate degraded mode with orphaned clusters
      :ets.insert(:metadata, {
        :orphaned_clusters,
        %{
          "cluster-orphaned-1" => ["node-uuid-5", "node-uuid-6"],
          "cluster-orphaned-2" => ["node-uuid-7"]
        }
      })

      conn = get(conn, ~p"/api/admins/orphaned_clusters")
      response = json_response(conn, 200)

      # Should have both orphaned clusters
      assert Map.has_key?(response, "cluster-orphaned-1")
      assert Map.has_key?(response, "cluster-orphaned-2")

      # Check node lists for each orphaned cluster
      assert response["cluster-orphaned-1"] == ["node-uuid-5", "node-uuid-6"]
      assert response["cluster-orphaned-2"] == ["node-uuid-7"]
    end

    test "returns single orphaned cluster with multiple nodes", %{conn: conn} do
      :ets.insert(:metadata, {
        :orphaned_clusters,
        %{
          "cluster-huge" => ["n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8", "n9", "n10"]
        }
      })

      conn = get(conn, ~p"/api/admins/orphaned_clusters")
      response = json_response(conn, 200)

      assert length(response["cluster-huge"]) == 10
    end

    test "returns multiple orphaned clusters with various node counts", %{conn: conn} do
      :ets.insert(:metadata, {
        :orphaned_clusters,
        %{
          "cluster-a" => ["n1"],
          "cluster-b" => ["n2", "n3", "n4"],
          "cluster-c" => [],
          "cluster-d" => ["n5", "n6"]
        }
      })

      conn = get(conn, ~p"/api/admins/orphaned_clusters")
      response = json_response(conn, 200)

      assert length(response["cluster-a"]) == 1
      assert length(response["cluster-b"]) == 3
      assert length(response["cluster-c"]) == 0
      assert length(response["cluster-d"]) == 2
    end

    test "handles orphaned cluster with empty node list", %{conn: conn} do
      :ets.insert(:metadata, {
        :orphaned_clusters,
        %{
          "cluster-empty-orphaned" => []
        }
      })

      conn = get(conn, ~p"/api/admins/orphaned_clusters")
      response = json_response(conn, 200)

      assert response["cluster-empty-orphaned"] == []
    end

    test "returns consistent format matching OpenAPI schema", %{conn: conn} do
      :ets.insert(:metadata, {
        :orphaned_clusters,
        %{
          "cluster-test" => ["node-1", "node-2"]
        }
      })

      conn = get(conn, ~p"/api/admins/orphaned_clusters")
      response = json_response(conn, 200)

      # Verify it's a map with cluster names as keys and node arrays as values
      assert is_map(response)
      assert is_list(response["cluster-test"])
      assert Enum.all?(response["cluster-test"], &is_binary/1)
    end
  end
end
