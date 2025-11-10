# edge_admin/test/edge_admin_web/controllers/nodes/node_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.NodeControllerTest do
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
      conn = patch(conn, ~p"/api/nodes/#{node}", node: @update_attrs)

      response = json_response(conn, 200)["data"]
      assert response["status"] == "offline"
      assert response["vpn_ip"] == "100.64.0.2"
    end

    test "handles validation errors on update", %{conn: conn} do
      node = node_fixture()
      conn = patch(conn, ~p"/api/nodes/#{node}", node: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete node" do
    test "deletes chosen node", %{conn: conn} do
      node = node_fixture()
      conn = delete(conn, ~p"/api/nodes/#{node}")
      assert response(conn, 204)

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/nodes/#{node}")
      end)
    end

    test "returns 404 for non-existent node", %{conn: conn} do
      assert_error_sent(404, fn ->
        delete(conn, ~p"/api/nodes/00000000-0000-0000-0000-000000000000")
      end)
    end
  end
end
