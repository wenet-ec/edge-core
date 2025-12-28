# edge_admin/test/edge_admin_web/controllers/agents/node_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Agents.NodeControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures
  import Mox

  setup :verify_on_exit!

  @valid_attrs %{
    "node_id" => "node-abc-123",
    "id_type" => "persistent",
    "cluster_id" => nil,
    # Will be set in setup
    "http_port" => 44_000,
    "ssh_port" => 42_222,
    "metrics_port" => 49_100,
    "http_proxy_port" => 44_880,
    "socks5_proxy_port" => 44_180,
    "version" => "1.0.0",
    "self_update_enabled" => true
  }

  setup %{conn: conn} do
    cluster = cluster_fixture()
    attrs = Map.put(@valid_attrs, "cluster_id", cluster.id)

    {:ok, conn: put_req_header(conn, "accept", "application/json"), cluster: cluster, attrs: attrs}
  end

  describe "POST /api/agents/nodes (node registration)" do
    test "registers new node successfully", %{conn: conn, cluster: cluster, attrs: attrs} do
      # Mock Netmaker API call
      expect(NexmakerMock, :get_node, fn _network_name, _node_id ->
        {:ok, %{"hostid" => "netmaker-host-123"}}
      end)

      conn = post(conn, ~p"/api/agents/nodes", attrs)

      assert %{
               "api_token" => api_token,
               "proxy_password" => proxy_password,
               "node_id" => node_id,
               "cluster_id" => cluster_id
             } = json_response(conn, 201)

      assert node_id == attrs["node_id"]
      assert cluster_id == cluster.id
      assert is_binary(api_token)
      assert is_binary(proxy_password)
      assert byte_size(api_token) > 0
      assert byte_size(proxy_password) > 0

      # Verify node was created in database
      node = EdgeAdmin.Repo.get(EdgeAdmin.Nodes.Node, node_id)
      assert node.cluster_id == cluster.id
      assert node.api_token == api_token
      assert node.proxy_password == proxy_password
      assert node.status == "online"
    end

    test "generates new tokens when re-registering", %{
      conn: conn,
      cluster: cluster,
      attrs: attrs
    } do
      # Mock Netmaker API call
      expect(NexmakerMock, :get_node, 2, fn _network_name, _node_id ->
        {:ok, %{"hostid" => "netmaker-host-123"}}
      end)

      # First registration
      conn1 = post(conn, ~p"/api/agents/nodes", attrs)
      response1 = json_response(conn1, 201)
      first_api_token = response1["api_token"]
      first_proxy_password = response1["proxy_password"]

      # Second registration (same node)
      conn2 = post(conn, ~p"/api/agents/nodes", attrs)
      response2 = json_response(conn2, 201)

      # Tokens should be DIFFERENT (regenerated on every registration)
      assert response2["api_token"] != first_api_token
      assert response2["proxy_password"] != first_proxy_password
      assert is_binary(response2["api_token"])
      assert is_binary(response2["proxy_password"])
    end

    test "returns error when cluster doesn't exist", %{conn: conn, attrs: attrs} do
      attrs = Map.put(attrs, "cluster_id", Ecto.UUID.generate())

      conn = post(conn, ~p"/api/agents/nodes", attrs)

      assert json_response(conn, 404)
    end

    test "returns error when node doesn't exist in Netmaker", %{conn: conn, attrs: attrs} do
      # Mock Netmaker API call to return not found
      expect(NexmakerMock, :get_node, fn _network_name, _node_id ->
        {:error, :not_found}
      end)

      conn = post(conn, ~p"/api/agents/nodes", attrs)

      assert %{"error" => "Node not found in Netmaker network"} = json_response(conn, 403)
    end

    test "validates required fields", %{conn: conn, cluster: cluster} do
      invalid_attrs = %{
        "node_id" => "test-node",
        "cluster_id" => cluster.id
        # Missing required fields
      }

      conn = post(conn, ~p"/api/agents/nodes", invalid_attrs)

      assert json_response(conn, 422)
    end
  end
end
