# edge_admin/test/edge_admin/nodes_test.exs
defmodule EdgeAdmin.NodesTest do
  use EdgeAdmin.DataCase

  alias EdgeAdmin.Nodes

  describe "nodes" do
    alias EdgeAdmin.Nodes.Node

    import EdgeAdmin.NodesFixtures

    # Updated invalid attrs - only hardware_id is required now
    @invalid_attrs %{hardware_id: nil}

    test "list_nodes/0 returns all nodes" do
      node = node_fixture()
      assert Nodes.list_nodes() == [node]
    end

    test "get_node!/1 returns the node with given id" do
      node = node_fixture()
      assert Nodes.get_node!(node.id) == node
    end

    test "create_node/1 with valid data creates a node" do
      valid_attrs = %{
        hardware_id: "some-hardware-id",
        status: "online",
        vpn_ip: "100.64.0.1",
        last_seen_at: ~U[2025-06-08 08:12:00Z]
      }

      assert {:ok, %Node{} = node} = Nodes.create_node(valid_attrs)
      assert node.hardware_id == "some-hardware-id"
      assert node.status == "online"
      assert node.vpn_ip == "100.64.0.1"
      assert node.last_seen_at == ~U[2025-06-08 08:12:00Z]
      # Test virtual field
      assert node.vpn_hostname == "node-#{node.id}"
    end

    test "create_node/1 with minimal data creates a node" do
      valid_attrs = %{hardware_id: "minimal-hardware-id"}

      assert {:ok, %Node{} = node} = Nodes.create_node(valid_attrs)
      assert node.hardware_id == "minimal-hardware-id"
      assert is_nil(node.status)
      assert is_nil(node.vpn_ip)
      assert is_nil(node.last_seen_at)
      # Virtual field should still work
      assert node.vpn_hostname == "node-#{node.id}"
    end

    test "create_node/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Nodes.create_node(@invalid_attrs)
    end

    test "update_node/2 with valid data updates the node" do
      node = node_fixture()
      update_attrs = %{
        status: "offline",
        hardware_id: "updated-hardware-id",
        vpn_ip: "100.64.0.2",
        last_seen_at: ~U[2025-06-09 08:12:00Z]
      }

      assert {:ok, %Node{} = updated_node} = Nodes.update_node(node, update_attrs)
      assert updated_node.status == "offline"
      assert updated_node.hardware_id == "updated-hardware-id"
      assert updated_node.vpn_ip == "100.64.0.2"
      assert updated_node.last_seen_at == ~U[2025-06-09 08:12:00Z]
      # Virtual field should remain consistent
      assert updated_node.vpn_hostname == "node-#{updated_node.id}"
    end

    test "update_node/2 with invalid data returns error changeset" do
      node = node_fixture()
      assert {:error, %Ecto.Changeset{}} = Nodes.update_node(node, @invalid_attrs)
      assert node == Nodes.get_node!(node.id)
    end

    test "delete_node/1 deletes the node" do
      node = node_fixture()
      assert {:ok, %Node{}} = Nodes.delete_node(node)
      assert_raise Ecto.NoResultsError, fn -> Nodes.get_node!(node.id) end
    end

    test "change_node/1 returns a node changeset" do
      node = node_fixture()
      assert %Ecto.Changeset{} = Nodes.change_node(node)
    end

    test "vpn_hostname/1 computes hostname from node ID" do
      node = node_fixture()
      assert Node.vpn_hostname(node) == "node-#{node.id}"
    end

    test "vpn_hostname/1 returns nil for node without ID" do
      node = %Node{id: nil}
      assert Node.vpn_hostname(node) == nil
    end
  end
end
