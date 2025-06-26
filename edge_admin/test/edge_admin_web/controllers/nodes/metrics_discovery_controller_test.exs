# edge_admin/test/edge_admin_web/controllers/nodes/metrics_discovery_controller_test.exs
defmodule EdgeAdminWeb.Nodes.MetricsDiscoveryControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "returns empty array when no nodes exist", %{conn: conn} do
      conn = get(conn, ~p"/api/metrics/discovery")

      assert json_response(conn, 200) == []
    end

    test "returns empty array when nodes exist but have no VPN IPs", %{conn: conn} do
      # Create a node without VPN IP
      node_fixture(%{vpn_ip: nil})

      conn = get(conn, ~p"/api/metrics/discovery")

      assert json_response(conn, 200) == []
    end

    test "returns empty array when nodes have empty VPN IPs", %{conn: conn} do
      # Create a node with empty VPN IP
      node_fixture(%{vpn_ip: ""})

      conn = get(conn, ~p"/api/metrics/discovery")

      assert json_response(conn, 200) == []
    end

    test "returns discovery targets when nodes have VPN IPs", %{conn: conn} do
      # Create nodes with VPN IPs (using different IPs than the default)
      node_fixture(%{vpn_ip: "100.64.0.10"})
      node_fixture(%{vpn_ip: "100.64.0.11"})

      conn = get(conn, ~p"/api/metrics/discovery")
      response = json_response(conn, 200)

      # Should return array with one target group
      assert is_list(response)
      assert length(response) == 1

      [target_group] = response

      # Verify target group structure
      assert Map.has_key?(target_group, "targets")
      assert Map.has_key?(target_group, "labels")

      # Verify targets contain the expected endpoints
      targets = target_group["targets"]
      assert is_list(targets)
      assert length(targets) == 2
      assert "100.64.0.10:9100" in targets
      assert "100.64.0.11:9100" in targets

      # Verify labels
      labels = target_group["labels"]
      assert labels["job"] == "edge-nodes"
      assert labels["scrape_source"] == "edge_admin_discovery"
    end

    test "only includes nodes with valid VPN IPs", %{conn: conn} do
      # Create mix of nodes - some with VPN IPs, some without
      # Should be included
      node_fixture(%{vpn_ip: "100.64.0.20"})
      # Should be excluded
      node_fixture(%{vpn_ip: nil})
      # Should be excluded
      node_fixture(%{vpn_ip: ""})
      # Should be included
      node_fixture(%{vpn_ip: "100.64.0.21"})

      conn = get(conn, ~p"/api/metrics/discovery")
      response = json_response(conn, 200)

      [target_group] = response
      targets = target_group["targets"]

      # Should only include the 2 nodes with valid VPN IPs
      assert length(targets) == 2
      assert "100.64.0.20:9100" in targets
      assert "100.64.0.21:9100" in targets
    end

    test "returns proper content type", %{conn: conn} do
      node_fixture(%{vpn_ip: "100.64.0.30"})

      conn = get(conn, ~p"/api/metrics/discovery")

      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end
  end
end
