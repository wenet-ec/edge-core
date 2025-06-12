# edge_admin/test/edge_admin/nodes_test.exs
defmodule EdgeAdmin.NodesTest do
  use EdgeAdmin.DataCase

  alias EdgeAdmin.Nodes

  describe "nodes" do
    alias EdgeAdmin.Nodes.Node

    import EdgeAdmin.NodesFixtures

    # Updated invalid attrs - only id is required now
    @invalid_attrs %{id: nil}

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
        id: "bc9ebeb196a44dfd953e899a61637577",  # Use valid 32-char hex
        status: "online",
        vpn_ip: "100.64.0.1",
        last_seen_at: ~U[2025-06-08 08:12:00Z]
      }

      assert {:ok, %Node{} = node} = Nodes.create_node(valid_attrs)
      # After normalization, it should be in UUID format
      assert node.id == "bc9ebeb1-96a4-4dfd-953e-899a61637577"
      assert node.status == "online"
      assert node.vpn_ip == "100.64.0.1"
      assert node.last_seen_at == ~U[2025-06-08 08:12:00Z]
      # Test virtual field
      assert node.vpn_hostname == "node-#{node.id}"
    end

    test "create_node/1 with minimal data creates a node" do
      hardware_id = "bc9ebeb196a44dfd953e899a61637577"
      valid_attrs = %{id: hardware_id}

      assert {:ok, %Node{} = node} = Nodes.create_node(valid_attrs)
      assert node.id == "bc9ebeb1-96a4-4dfd-953e-899a61637577"
      assert is_nil(node.status)
      assert is_nil(node.vpn_ip)
      assert is_nil(node.last_seen_at)
      # Virtual field should still work
      assert node.vpn_hostname == "node-#{node.id}"
    end

    test "create_node/1 accepts hardware ID with dashes" do
      hardware_id = "bc9ebeb1-96a4-4dfd-953e-899a61637577"
      valid_attrs = %{id: hardware_id}

      assert {:ok, %Node{} = node} = Nodes.create_node(valid_attrs)
      assert node.id == "bc9ebeb1-96a4-4dfd-953e-899a61637577"
    end

    test "create_node/1 rejects invalid hardware ID format" do
      invalid_attrs = %{id: "invalid-hardware-id"}

      assert {:error, %Ecto.Changeset{} = changeset} = Nodes.create_node(invalid_attrs)
      assert changeset.errors[:id] != nil
    end

    test "create_node/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Nodes.create_node(@invalid_attrs)
    end

    test "update_node/2 with valid data updates the node" do
      node = node_fixture()
      update_attrs = %{
        status: "offline",
        vpn_ip: "100.64.0.2",
        last_seen_at: ~U[2025-06-09 08:12:00Z]
      }

      assert {:ok, %Node{} = updated_node} = Nodes.update_node(node, update_attrs)
      assert updated_node.status == "offline"
      assert updated_node.vpn_ip == "100.64.0.2"
      assert updated_node.last_seen_at == ~U[2025-06-09 08:12:00Z]
      # Virtual field should remain consistent
      assert updated_node.vpn_hostname == "node-#{updated_node.id}"
      # ID should remain the same
      assert updated_node.id == node.id
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

    test "create_node/1 with duplicate id returns error changeset" do
      # Use valid hardware ID format
      id = "bc9ebeb196a44dfd953e899a61637577"
      assert {:ok, %Node{}} = Nodes.create_node(%{id: id})

      # Try to create second node with same id
      assert {:error, %Ecto.Changeset{} = changeset} = Nodes.create_node(%{id: id})

      # Should have a primary key constraint error
      assert changeset.errors[:id] != nil or changeset.action == :insert
    end
  end
end
