# edge_admin/test/edge_admin/nodes_test.exs
defmodule EdgeAdmin.NodesTest do
  use EdgeAdmin.DataCase

  alias EdgeAdmin.Nodes

  describe "nodes" do
    alias EdgeAdmin.Nodes.Node

    import EdgeAdmin.NodesFixtures

    @invalid_attrs %{id: nil, vpn_ip: nil, last_seen_at: nil, status: nil, id_type: nil}

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
        id: "bc9ebeb1-96a4-4dfd-953e-899a61637577",
        id_type: "machine_id",
        status: "online",
        vpn_ip: "100.64.0.1",
        last_seen_at: ~U[2025-06-08 08:12:00Z]
      }

      assert {:ok, %Node{} = node} = Nodes.create_node(valid_attrs)
      assert node.id == "bc9ebeb1-96a4-4dfd-953e-899a61637577"
      assert node.id_type == "machine_id"
      assert node.status == "online"
      assert node.vpn_ip == "100.64.0.1"
      assert node.last_seen_at == ~U[2025-06-08 08:12:00Z]
      # Test virtual field
      assert node.vpn_hostname == "node-#{node.id}"
    end

    test "create_node/1 with minimal data creates a node" do
      valid_attrs = %{
        id: "01234567-8901-2345-6789-012345678901",
        id_type: "hardware_id"
      }

      assert {:ok, %Node{} = node} = Nodes.create_node(valid_attrs)
      assert node.id == "01234567-8901-2345-6789-012345678901"
      assert node.id_type == "hardware_id"
      assert is_nil(node.status)
      assert is_nil(node.vpn_ip)
      assert is_nil(node.last_seen_at)
      # Virtual field should still work
      assert node.vpn_hostname == "node-#{node.id}"
    end

    test "create_node/1 validates id_type field" do
      # Test valid id_types - use unique UUIDs for each
      for id_type <- ["machine_id", "hardware_id", "temporary_id"] do
        uuid = Ecto.UUID.generate()
        valid_attrs = %{id: uuid, id_type: id_type}
        assert {:ok, %Node{}} = Nodes.create_node(valid_attrs)
      end

      invalid_uuid = Ecto.UUID.generate()
      invalid_attrs = %{id: invalid_uuid, id_type: "invalid_type"}
      assert {:error, %Ecto.Changeset{} = changeset} = Nodes.create_node(invalid_attrs)
      assert changeset.errors[:id_type] != nil
    end

    test "create_node/1 rejects invalid UUID format" do
      invalid_formats = [
        "invalid-uuid",
        # No dashes
        "bc9ebeb196a44dfd953e899a61637577",
        # Too short
        "bc9ebeb1-96a4-4dfd-953e",
        # Too long
        "bc9ebeb1-96a4-4dfd-953e-899a61637577-extra",
        "not-a-uuid-at-all"
      ]

      for invalid_id <- invalid_formats do
        invalid_attrs = %{id: invalid_id, id_type: "machine_id"}
        assert {:error, %Ecto.Changeset{} = changeset} = Nodes.create_node(invalid_attrs)
        # Check that the error is on the id field
        assert Keyword.has_key?(changeset.errors, :id)
      end
    end

    test "create_node/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Nodes.create_node(@invalid_attrs)
    end

    test "update_node/2 with valid data updates the node" do
      node = node_fixture()

      update_attrs = %{
        status: "offline",
        vpn_ip: "100.64.0.2",
        last_seen_at: ~U[2025-06-09 08:12:00Z],
        id_type: "hardware_id"
      }

      assert {:ok, %Node{} = updated_node} = Nodes.update_node(node, update_attrs)
      assert updated_node.status == "offline"
      assert updated_node.vpn_ip == "100.64.0.2"
      assert updated_node.last_seen_at == ~U[2025-06-09 08:12:00Z]
      assert updated_node.id_type == "hardware_id"
      assert updated_node.vpn_hostname == "node-#{updated_node.id}"
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

    test "temporary?/1 and persistent?/1 helpers" do
      # Test temporary node
      temp_node = %Node{id_type: "temporary_id"}
      assert Node.temporary?(temp_node) == true
      assert Node.persistent?(temp_node) == false

      # Test persistent nodes
      machine_node = %Node{id_type: "machine_id"}
      assert Node.temporary?(machine_node) == false
      assert Node.persistent?(machine_node) == true

      hardware_node = %Node{id_type: "hardware_id"}
      assert Node.temporary?(hardware_node) == false
      assert Node.persistent?(hardware_node) == true

      # Test node without id_type
      unknown_node = %Node{id_type: nil}
      assert Node.temporary?(unknown_node) == false
      assert Node.persistent?(unknown_node) == false
    end
  end

  describe "filtering and pagination integration" do
    test "apply_filtering_pagination/1 uses correct field configurations" do
      # Create some test nodes
      {:ok, _node1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id", status: "online"})

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", status: "offline"})

      # Test that it returns a FilteringPagination struct
      result = Nodes.apply_filtering_pagination(%{})
      assert %EdgeAdmin.FilteringPagination{} = result
      assert length(result.data) == 2
    end

    test "apply_filtering_pagination/1 respects filterable fields configuration" do
      {:ok, _node1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id", status: "online"})

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", status: "offline"})

      # Test status filtering (should work - it's in filterable_fields)
      result = Nodes.apply_filtering_pagination(%{"status" => "online"})
      assert length(result.data) == 1
      assert hd(result.data).status == "online"

      # Test that non-filterable fields are ignored
      result = Nodes.apply_filtering_pagination(%{"non_existent_field" => "value"})
      assert result.filters == %{}
      # No filtering applied
      assert length(result.data) == 2
    end

    test "apply_filtering_pagination/1 respects sortable fields configuration" do
      {:ok, _node1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id", status: "online"})

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", status: "offline"})

      # Test valid sortable field
      result = Nodes.apply_filtering_pagination(%{"sort" => "status:desc"})
      assert result.sort == [{:status, :desc}]

      # Test that non-sortable fields are ignored
      result = Nodes.apply_filtering_pagination(%{"sort" => "non_existent_field:asc"})
      assert result.sort == []
    end

    test "apply_filtering_pagination/1 uses correct default sort" do
      {:ok, _node} = Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id"})

      result = Nodes.apply_filtering_pagination(%{})
      # Should use default sort "inserted_at:desc"
      assert result.sort == [{:inserted_at, :desc}]
    end
  end

  describe "list_nodes_with_filtering_pagination/1" do
    test "populates virtual fields for paginated results" do
      {:ok, _node1} = Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id"})
      {:ok, _node2} = Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id"})

      result = Nodes.list_nodes_with_filtering_pagination(%{})

      assert %EdgeAdmin.FilteringPagination{} = result
      assert length(result.data) == 2

      # Test that virtual fields are populated
      Enum.each(result.data, fn node ->
        assert node.vpn_hostname == "node-#{node.id}"
      end)
    end

    test "combines filtering and virtual field population" do
      {:ok, _node1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id", status: "online"})

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", status: "offline"})

      result = Nodes.list_nodes_with_filtering_pagination(%{"status" => "online"})

      assert length(result.data) == 1
      node = hd(result.data)
      assert node.status == "online"
      # Virtual field populated
      assert node.vpn_hostname == "node-#{node.id}"
    end

    test "handles empty results" do
      result = Nodes.list_nodes_with_filtering_pagination(%{"status" => "nonexistent"})

      assert result.data == []
      assert result.total == 0
    end

    test "preserves pagination metadata" do
      # Create 3 nodes
      for _ <- 1..3 do
        {:ok, _node} = Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id"})
      end

      result = Nodes.list_nodes_with_filtering_pagination(%{"page_size" => "2"})

      assert result.page_size == 2
      assert result.total == 3
      assert result.total_pages == 2
      assert result.has_next == true
      assert length(result.data) == 2
    end
  end
end
