# edge_admin/test/edge_admin_web/controllers/admins/admin_cluster_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Admins.AdminClusterControllerTest do
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

    # Insert test admin cluster data
    :ets.insert(:metadata, {:admin_cluster, %{
      name: "admin-cluster-test",
      total_admins: 2,
      degraded: false,
      topology: [
        %{
          id: "admin-test123456",
          max_capacity: 100,
          erlang_node_name: :"admin@admin-test123456.admin-cluster-test.nm.internal"
        },
        %{
          id: "admin-peer789012",
          max_capacity: 200,
          erlang_node_name: :"admin@admin-peer789012.admin-cluster-test.nm.internal"
        }
      ]
    }})
  end

  describe "GET /api/admins/admin_cluster" do
    test "returns admin cluster topology from ETS", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/admin_cluster")
      response = json_response(conn, 200)

      assert response["name"] == "admin-cluster-test"
      assert response["total_admins"] == 2
      assert response["degraded"] == false
      assert length(response["topology"]) == 2
    end

    test "topology entries have correct structure", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/admin_cluster")
      response = json_response(conn, 200)

      first_admin = Enum.find(response["topology"], fn a -> a["id"] == "admin-test123456" end)

      assert first_admin["id"] == "admin-test123456"
      assert first_admin["max_capacity"] == 100
      assert first_admin["erlang_node_name"] == "admin@admin-test123456.admin-cluster-test.nm.internal"
    end

    test "erlang_node_names in topology are converted to strings", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/admin_cluster")
      response = json_response(conn, 200)

      Enum.each(response["topology"], fn entry ->
        assert is_binary(entry["erlang_node_name"])
      end)
    end

    test "handles degraded mode", %{conn: conn} do
      # Update ETS with degraded state
      :ets.insert(:metadata, {:admin_cluster, %{
        name: "admin-cluster-test",
        total_admins: 1,
        degraded: true,
        topology: [
          %{
            id: "admin-test123456",
            max_capacity: 100,
            erlang_node_name: :"admin@admin-test123456.admin-cluster-test.nm.internal"
          }
        ]
      }})

      conn = get(conn, ~p"/api/admins/admin_cluster")
      response = json_response(conn, 200)

      assert response["degraded"] == true
      assert response["total_admins"] == 1
    end

    test "handles empty topology", %{conn: conn} do
      # Update ETS with empty topology
      :ets.insert(:metadata, {:admin_cluster, %{
        name: "admin-cluster-test",
        total_admins: 0,
        degraded: false,
        topology: []
      }})

      conn = get(conn, ~p"/api/admins/admin_cluster")
      response = json_response(conn, 200)

      assert response["topology"] == []
      assert response["total_admins"] == 0
    end
  end
end
