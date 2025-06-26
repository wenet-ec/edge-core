# test/edge_admin_web/controllers/nodes/metrics_controller_test.exs
defmodule EdgeAdminWeb.Nodes.MetricsControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "returns node_not_found for invalid node ID", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn = get(conn, ~p"/api/nodes/#{fake_id}/metrics")

      response = json_response(conn, 404)
      assert response["error"] == "Node not found"
    end

    test "returns metrics_unavailable when node has no VPN IP", %{conn: conn} do
      node = node_fixture(%{vpn_ip: nil})

      conn = get(conn, ~p"/api/nodes/#{node.id}/metrics")

      response = json_response(conn, 503)
      assert response["error"] == "Metrics service unavailable"
    end

    test "returns metrics_unavailable when node has empty VPN IP", %{conn: conn} do
      node = node_fixture(%{vpn_ip: ""})

      conn = get(conn, ~p"/api/nodes/#{node.id}/metrics")

      response = json_response(conn, 503)
      assert response["error"] == "Metrics service unavailable"
    end

    test "returns metrics_unavailable when metrics storage URL is not configured", %{conn: conn} do
      node = node_fixture(%{vpn_ip: "100.64.0.1"})

      # Remove the config
      original_url = Application.get_env(:edge_admin, :metrics_storage_url)
      Application.delete_env(:edge_admin, :metrics_storage_url)

      try do
        conn = get(conn, ~p"/api/nodes/#{node.id}/metrics")

        response = json_response(conn, 503)
        assert response["error"] == "Metrics service unavailable"
      after
        Application.put_env(:edge_admin, :metrics_storage_url, original_url)
      end
    end
  end
end
