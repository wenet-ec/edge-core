# edge_admin/test/edge_admin_web/controllers/admins/edge_clusters_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Admins.EdgeClustersControllerTest do
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
    :ets.insert(:metadata, {:admin, %{
      id: "admin-test123456",
      max_capacity: 100,
      erlang_node_name: :"admin@admin-test123456.admin-cluster-test.nm.internal",
      dns_hostname: "admin-test123456.admin-cluster-test.nm.internal",
      admin_cluster_name: "admin-cluster-test",
      last_computed_at: ~U[2025-01-15 12:00:00Z]
    }})

    # Insert test edge clusters data
    :ets.insert(:metadata, {:edge_clusters, %{
      "admin-test123456" => %{
        "cluster-abc123" => ["node-uuid-1", "node-uuid-2"],
        "cluster-def456" => ["node-uuid-x"]
      },
      "admin-peer789012" => %{
        "cluster-ghi789" => [],
        "cluster-jkl012" => ["node-uuid-3"]
      }
    }})
  end

  describe "GET /api/admins/edge_clusters" do
    test "returns all edge clusters from all admins", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/edge_clusters")
      response = json_response(conn, 200)

      # Should have both admins
      assert Map.has_key?(response, "admin-test123456")
      assert Map.has_key?(response, "admin-peer789012")

      # Check clusters for each admin
      assert Map.has_key?(response["admin-test123456"], "cluster-abc123")
      assert Map.has_key?(response["admin-test123456"], "cluster-def456")
      assert Map.has_key?(response["admin-peer789012"], "cluster-ghi789")
      assert Map.has_key?(response["admin-peer789012"], "cluster-jkl012")
    end

    test "returns correct node lists for each cluster", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/edge_clusters")
      response = json_response(conn, 200)

      assert response["admin-test123456"]["cluster-abc123"] == ["node-uuid-1", "node-uuid-2"]
      assert response["admin-test123456"]["cluster-def456"] == ["node-uuid-x"]
      assert response["admin-peer789012"]["cluster-ghi789"] == []
      assert response["admin-peer789012"]["cluster-jkl012"] == ["node-uuid-3"]
    end

    test "handles empty edge_clusters map", %{conn: conn} do
      :ets.insert(:metadata, {:edge_clusters, %{}})

      conn = get(conn, ~p"/api/admins/edge_clusters")
      response = json_response(conn, 200)

      assert response == %{}
    end

    test "handles admin with no clusters", %{conn: conn} do
      :ets.insert(:metadata, {:edge_clusters, %{
        "admin-test123456" => %{},
        "admin-peer789012" => %{
          "cluster-ghi789" => ["node-1"]
        }
      }})

      conn = get(conn, ~p"/api/admins/edge_clusters")
      response = json_response(conn, 200)

      assert response["admin-test123456"] == %{}
      assert response["admin-peer789012"]["cluster-ghi789"] == ["node-1"]
    end

    test "handles empty node lists", %{conn: conn} do
      :ets.insert(:metadata, {:edge_clusters, %{
        "admin-test123456" => %{
          "cluster-empty" => []
        }
      }})

      conn = get(conn, ~p"/api/admins/edge_clusters")
      response = json_response(conn, 200)

      assert response["admin-test123456"]["cluster-empty"] == []
    end

    test "returns multiple admins with various cluster configurations", %{conn: conn} do
      :ets.insert(:metadata, {:edge_clusters, %{
        "admin-1" => %{
          "cluster-a" => ["n1", "n2", "n3", "n4", "n5"],
          "cluster-b" => ["n6"]
        },
        "admin-2" => %{
          "cluster-c" => [],
          "cluster-d" => ["n7", "n8"]
        },
        "admin-3" => %{}
      }})

      conn = get(conn, ~p"/api/admins/edge_clusters")
      response = json_response(conn, 200)

      assert length(response["admin-1"]["cluster-a"]) == 5
      assert length(response["admin-1"]["cluster-b"]) == 1
      assert length(response["admin-2"]["cluster-c"]) == 0
      assert length(response["admin-2"]["cluster-d"]) == 2
      assert response["admin-3"] == %{}
    end
  end
end
