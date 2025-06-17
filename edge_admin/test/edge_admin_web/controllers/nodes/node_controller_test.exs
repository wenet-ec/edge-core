# edge_admin/test/edge_admin_web/controllers/nodes/node_controller_test.exs
defmodule EdgeAdminWeb.Nodes.NodeControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures

  @create_attrs %{
    id: "bc9ebeb1-96a4-4dfd-953e-899a61637577",
    id_type: "machine_id",
    status: "online",
    vpn_ip: "100.64.0.1"
  }

  @update_attrs %{
    status: "offline",
    vpn_ip: "100.64.0.2"
  }

  @invalid_attrs %{id: nil}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists nodes", %{conn: conn} do
      conn = get(conn, ~p"/api/nodes")
      assert json_response(conn, 200)["data"] == []

      node = node_fixture()
      conn = get(conn, ~p"/api/nodes")

      [response_node] = json_response(conn, 200)["data"]
      assert response_node["id"] == node.id
    end
  end

  describe "create node" do
    test "creates node with valid data", %{conn: conn} do
      conn = post(conn, ~p"/api/nodes", node: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/nodes/#{id}")
      response = json_response(conn, 200)["data"]

      assert response["id"] == id
      assert response["status"] == "online"
      assert response["id_type"] == "machine_id"
    end

    test "handles validation errors", %{conn: conn} do
      conn = post(conn, ~p"/api/nodes", node: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "prevents duplicate node IDs", %{conn: conn} do
      post(conn, ~p"/api/nodes", node: @create_attrs)
      conn = post(conn, ~p"/api/nodes", node: @create_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "show node" do
    test "returns node by ID", %{conn: conn} do
      node = node_fixture()
      conn = get(conn, ~p"/api/nodes/#{node}")

      response = json_response(conn, 200)["data"]
      assert response["id"] == node.id
    end
  end

  describe "update node" do
    test "updates node with valid data", %{conn: conn} do
      node = node_fixture()
      conn = put(conn, ~p"/api/nodes/#{node}", node: @update_attrs)

      response = json_response(conn, 200)["data"]
      assert response["status"] == "offline"
      assert response["vpn_ip"] == "100.64.0.2"
    end

    test "handles validation errors on update", %{conn: conn} do
      node = node_fixture()
      conn = put(conn, ~p"/api/nodes/#{node}", node: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end
  end
end
