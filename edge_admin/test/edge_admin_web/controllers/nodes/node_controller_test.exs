# edge_admin/lib/edge_admin_web/controllers/nodes/node_controller_test.exs
defmodule EdgeAdminWeb.Nodes.NodeControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures

  alias EdgeAdmin.Nodes.Node

  # Updated test data to reflect our validation changes
  @create_attrs %{
    hardware_id: "test-hardware-id-123",
    status: "online",
    vpn_ip: "100.64.0.1",
    last_seen_at: ~U[2025-06-08 08:20:00Z]
  }

  @minimal_create_attrs %{
    hardware_id: "minimal-hardware-id-456"
  }

  @update_attrs %{
    status: "offline",
    hardware_id: "updated-hardware-id-789",
    vpn_ip: "100.64.0.2",
    last_seen_at: ~U[2025-06-09 08:20:00Z]
  }

  # Only hardware_id is required now
  @invalid_attrs %{hardware_id: nil}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all nodes", %{conn: conn} do
      conn = get(conn, ~p"/api/nodes")
      assert json_response(conn, 200)["data"] == []
    end

    test "lists all nodes with existing data", %{conn: conn} do
      node = node_fixture()
      conn = get(conn, ~p"/api/nodes")

      [response_node] = json_response(conn, 200)["data"]
      assert response_node["id"] == node.id
      assert response_node["hardware_id"] == node.hardware_id
      assert response_node["vpn_hostname"] == "node-#{node.id}"
    end
  end

  describe "create node" do
    test "renders node when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/api/nodes", node: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/nodes/#{id}")

      assert %{
               "id" => ^id,
               "hardware_id" => "test-hardware-id-123",
               "last_seen_at" => "2025-06-08T08:20:00Z",
               "status" => "online",
               "vpn_ip" => "100.64.0.1",
               "vpn_hostname" => vpn_hostname
             } = json_response(conn, 200)["data"]

      # Test virtual field computation
      assert vpn_hostname == "node-#{id}"
    end

    test "renders node with minimal data", %{conn: conn} do
      conn = post(conn, ~p"/api/nodes", node: @minimal_create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/nodes/#{id}")

      assert %{
               "id" => ^id,
               "hardware_id" => "minimal-hardware-id-456",
               "last_seen_at" => nil,
               "status" => nil,
               "vpn_ip" => nil,
               "vpn_hostname" => vpn_hostname
             } = json_response(conn, 200)["data"]

      # Virtual field should still work with minimal data
      assert vpn_hostname == "node-#{id}"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/nodes", node: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "renders errors when hardware_id is not unique", %{conn: conn} do
      # Create first node
      post(conn, ~p"/api/nodes", node: @create_attrs)

      # Try to create second node with same hardware_id
      conn = post(conn, ~p"/api/nodes", node: @create_attrs)

      assert response = json_response(conn, 422)
      assert response["errors"] != %{}
      # Check that the error mentions hardware_id uniqueness
      assert Map.has_key?(response["errors"], "hardware_id")
    end
  end

  describe "show node" do
    setup [:create_node]

    test "renders node with vpn_hostname", %{conn: conn, node: node} do
      conn = get(conn, ~p"/api/nodes/#{node}")

      assert %{
        "id" => id,
        "hardware_id" => _,
        "vpn_hostname" => vpn_hostname
      } = json_response(conn, 200)["data"]

      assert id == node.id
      assert vpn_hostname == "node-#{node.id}"
    end
  end

  describe "update node" do
    setup [:create_node]

    test "renders node when data is valid", %{conn: conn, node: %Node{id: id} = node} do
      conn = put(conn, ~p"/api/nodes/#{node}", node: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, ~p"/api/nodes/#{id}")

      assert %{
               "id" => ^id,
               "hardware_id" => "updated-hardware-id-789",
               "last_seen_at" => "2025-06-09T08:20:00Z",
               "status" => "offline",
               "vpn_ip" => "100.64.0.2",
               "vpn_hostname" => vpn_hostname
             } = json_response(conn, 200)["data"]

      # Virtual field should remain consistent after update
      assert vpn_hostname == "node-#{id}"
    end

    test "renders errors when data is invalid", %{conn: conn, node: node} do
      conn = put(conn, ~p"/api/nodes/#{node}", node: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "can update individual fields", %{conn: conn, node: node} do
      # Test updating just status
      status_update = %{status: "maintenance"}
      conn = put(conn, ~p"/api/nodes/#{node}", node: status_update)

      assert %{"status" => "maintenance"} = json_response(conn, 200)["data"]

      # Test updating just vpn_ip
      conn = put(conn, ~p"/api/nodes/#{node}", node: %{vpn_ip: "100.64.0.99"})

      assert %{"vpn_ip" => "100.64.0.99"} = json_response(conn, 200)["data"]
    end
  end

  describe "delete node" do
    setup [:create_node]

    test "deletes chosen node", %{conn: conn, node: node} do
      conn = delete(conn, ~p"/api/nodes/#{node}")
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, ~p"/api/nodes/#{node}")
      end
    end
  end

  defp create_node(_) do
    node = node_fixture()
    %{node: node}
  end
end
