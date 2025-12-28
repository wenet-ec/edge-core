# edge_admin/test/edge_admin_web/controllers/admins/admin_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Admins.AdminControllerTest do
  use EdgeAdminWeb.ConnCase, async: true

  setup %{conn: conn} do
    # Set up the ETS table with test metadata
    setup_metadata_ets()

    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp setup_metadata_ets do
    # Create table if it doesn't exist (may already exist from other tests)
    if :ets.whereis(:metadata) == :undefined do
      :ets.new(:metadata, [:set, :public, :named_table, read_concurrency: true])
    end

    # Insert test admin data
    :ets.insert(
      :metadata,
      {:admin,
       %{
         id: "test123456",
         name: "admin-test123456",
         max_capacity: 100,
         erlang_node_name: :"admin@admin-test123456.admin-cluster-test.nm.internal",
         dns_hostname: "admin-test123456.admin-cluster-test.nm.internal",
         admin_cluster_name: "admin-cluster-test",
         last_computed_at: ~U[2025-01-15 12:00:00Z]
       }}
    )
  end

  describe "GET /api/admins/self" do
    test "returns admin identity from ETS", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/self")
      response = json_response(conn, 200)

      assert response["id"] == "test123456"
      assert response["name"] == "admin-test123456"
      assert response["max_capacity"] == 100
      assert response["erlang_node_name"] == "admin@admin-test123456.admin-cluster-test.nm.internal"
      assert response["dns_hostname"] == "admin-test123456.admin-cluster-test.nm.internal"
      assert response["admin_cluster_name"] == "admin-cluster-test"
      assert response["last_computed_at"] == "2025-01-15T12:00:00Z"
    end

    test "erlang_node_name is converted to string", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/self")
      response = json_response(conn, 200)

      # Should be a string, not an atom
      assert is_binary(response["erlang_node_name"])
    end

    test "handles nil last_computed_at", %{conn: conn} do
      # Update ETS with nil last_computed_at
      :ets.insert(
        :metadata,
        {:admin,
         %{
           id: "test123456",
           name: "admin-test123456",
           max_capacity: 100,
           erlang_node_name: :"admin@admin-test123456.admin-cluster-test.nm.internal",
           dns_hostname: "admin-test123456.admin-cluster-test.nm.internal",
           admin_cluster_name: "admin-cluster-test",
           last_computed_at: nil
         }}
      )

      conn = get(conn, ~p"/api/admins/self")
      response = json_response(conn, 200)

      assert response["last_computed_at"] == nil
    end
  end
end
