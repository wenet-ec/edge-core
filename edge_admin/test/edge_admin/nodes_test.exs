# edge_admin/test/edge_admin/nodes_test.exs
defmodule EdgeAdmin.NodesTest do
  use EdgeAdmin.DataCase

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Node
  alias EdgeAdmin.Nodes.SshUsername
  import EdgeAdmin.NodesFixtures

  describe "node validation and business rules" do
    test "validates UUID format" do
      # Valid UUID formats
      valid_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"
      assert {:ok, %Node{}} = Nodes.create_node(%{id: valid_uuid, id_type: "machine_id"})

      # Invalid UUID formats
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
        assert Keyword.has_key?(changeset.errors, :id)
      end
    end

    test "validates id_type field" do
      # Valid id_types
      for id_type <- ["machine_id", "hardware_id", "temporary_id"] do
        uuid = Ecto.UUID.generate()
        valid_attrs = %{id: uuid, id_type: id_type}
        assert {:ok, %Node{}} = Nodes.create_node(valid_attrs)
      end

      # Invalid id_type
      invalid_uuid = Ecto.UUID.generate()
      invalid_attrs = %{id: invalid_uuid, id_type: "invalid_type"}
      assert {:error, %Ecto.Changeset{} = changeset} = Nodes.create_node(invalid_attrs)
      assert changeset.errors[:id_type] != nil
    end

    test "populates virtual fields correctly" do
      # Test with full data
      full_attrs = %{
        id: "bc9ebeb1-96a4-4dfd-953e-899a61637577",
        id_type: "machine_id",
        status: "online",
        vpn_ip: "100.64.0.1",
        last_seen_at: ~U[2025-06-08 08:12:00Z]
      }

      assert {:ok, %Node{} = node} = Nodes.create_node(full_attrs)
      assert node.vpn_hostname == "node-#{node.id}"

      # Test with minimal data
      minimal_attrs = %{
        id: "01234567-8901-2345-6789-012345678901",
        id_type: "hardware_id"
      }

      assert {:ok, %Node{} = minimal_node} = Nodes.create_node(minimal_attrs)
      assert minimal_node.vpn_hostname == "node-#{minimal_node.id}"
      assert is_nil(minimal_node.status)
      assert is_nil(minimal_node.vpn_ip)
    end

    test "node classification helpers" do
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
    test "list_nodes_with_filtering_pagination handles basic functionality" do
      # Create test nodes
      {:ok, _node1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id", status: "online"})

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", status: "offline"})

      # Test basic functionality
      result = Nodes.list_nodes_with_filtering_pagination(%{})
      assert %EdgeAdmin.FilteringPagination{} = result
      assert length(result.data) == 2
      # Default sort
      assert result.sort == [{:inserted_at, :desc}]

      # Test status filtering (allowed field)
      result = Nodes.list_nodes_with_filtering_pagination(%{"status" => "online"})
      assert length(result.data) == 1
      assert hd(result.data).status == "online"

      # Test non-filterable fields are ignored
      result = Nodes.list_nodes_with_filtering_pagination(%{"non_existent_field" => "value"})
      assert result.filters == %{}
      assert length(result.data) == 2
    end

    test "supports sorting configuration" do
      {:ok, _node1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id", status: "online"})

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", status: "offline"})

      # Valid sortable field
      result = Nodes.list_nodes_with_filtering_pagination(%{"sort" => "status:desc"})
      assert result.sort == [{:status, :desc}]

      # Non-sortable fields are ignored
      result = Nodes.list_nodes_with_filtering_pagination(%{"sort" => "non_existent_field:asc"})
      assert result.sort == []
    end

    test "virtual field population in paginated results" do
      {:ok, _node1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id", status: "online"})

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", status: "offline"})

      # Test virtual fields are populated
      result = Nodes.list_nodes_with_filtering_pagination(%{})
      assert %EdgeAdmin.FilteringPagination{} = result
      assert length(result.data) == 2

      Enum.each(result.data, fn node ->
        assert node.vpn_hostname == "node-#{node.id}"
      end)

      # Test filtering + virtual fields
      result = Nodes.list_nodes_with_filtering_pagination(%{"status" => "online"})
      assert length(result.data) == 1
      node = hd(result.data)
      assert node.status == "online"
      assert node.vpn_hostname == "node-#{node.id}"
    end

    test "get_nodes_by_ids returns mixed results" do
      # Create a valid node
      {:ok, valid_node} = Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id"})
      invalid_id = Ecto.UUID.generate()

      # Test mixed valid/invalid IDs
      results = Nodes.get_nodes_by_ids([valid_node.id, invalid_id])

      assert length(results) == 2
      assert {:ok, returned_node} = Enum.at(results, 0)
      assert returned_node.id == valid_node.id
      assert {:error, "Node " <> ^invalid_id <> " not found"} = Enum.at(results, 1)

      # Test all valid IDs
      {:ok, valid_node2} = Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id"})
      results = Nodes.get_nodes_by_ids([valid_node.id, valid_node2.id])

      assert length(results) == 2
      assert Enum.all?(results, fn {status, _} -> status == :ok end)

      # Test empty list
      assert Nodes.get_nodes_by_ids([]) == []
    end

    test "handles edge cases" do
      # Empty results
      result = Nodes.list_nodes_with_filtering_pagination(%{"status" => "nonexistent"})
      assert result.data == []
      assert result.total == 0

      # Pagination metadata
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

  describe "ssh_usernames" do
    @invalid_attrs %{username: nil, node_id: nil}

    test "list_ssh_usernames_with_filtering_pagination basic functionality" do
      # Create test data
      node1 = node_fixture()
      node2 = node_fixture()
      _ssh_username1 = ssh_username_fixture(%{node_id: node1.id, username: "admin"})
      _ssh_username2 = ssh_username_fixture(%{node_id: node2.id, username: "user"})

      # Test basic pagination
      result = Nodes.list_ssh_usernames_with_filtering_pagination(%{})
      assert %EdgeAdmin.FilteringPagination{} = result
      assert length(result.data) == 2
      assert result.sort == [{:inserted_at, :desc}]

      # Test node_id filtering (most important filter for SSH usernames)
      result = Nodes.list_ssh_usernames_with_filtering_pagination(%{"node_id" => node1.id})
      assert length(result.data) == 1
      assert hd(result.data).node_id == node1.id
      assert hd(result.data).username == "admin"

      # Test username filtering with wildcard
      result = Nodes.list_ssh_usernames_with_filtering_pagination(%{"username" => "adm*"})
      assert length(result.data) == 1
      assert hd(result.data).username == "admin"
    end

    test "configuration matches expected fields" do
      # Just verify the filterable/sortable fields are what we expect
      # This catches configuration errors without retesting the filtering logic
      node = node_fixture()
      _ssh_username = ssh_username_fixture(%{node_id: node.id, username: "test"})

      # Test that all configured filterable fields work
      result =
        Nodes.list_ssh_usernames_with_filtering_pagination(%{
          "username" => "test",
          "node_id" => node.id
        })

      assert length(result.data) == 1

      # Test that all configured sortable fields work
      result =
        Nodes.list_ssh_usernames_with_filtering_pagination(%{
          "sort" => "username:asc"
        })

      assert result.sort == [{:username, :asc}]

      result =
        Nodes.list_ssh_usernames_with_filtering_pagination(%{
          "sort" => "inserted_at:desc"
        })

      assert result.sort == [{:inserted_at, :desc}]
    end

    test "create_ssh_username/1 with valid data creates a ssh_username" do
      node = node_fixture()
      valid_attrs = %{username: "john", node_id: node.id}

      assert {:ok, %SshUsername{} = ssh_username} = Nodes.create_ssh_username(valid_attrs)
      assert ssh_username.username == "john"
      assert ssh_username.node_id == node.id
    end

    test "create_ssh_username/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Nodes.create_ssh_username(@invalid_attrs)
    end

    test "create_ssh_username/1 enforces unique constraint per node" do
      node = node_fixture()
      attrs = %{username: "john", node_id: node.id}

      # First creation should succeed
      assert {:ok, %SshUsername{}} = Nodes.create_ssh_username(attrs)

      # Second creation with same username + node should fail
      assert {:error, %Ecto.Changeset{} = changeset} = Nodes.create_ssh_username(attrs)
      assert changeset.errors[:username] != nil or changeset.errors[:node_id] != nil
    end

    test "delete_ssh_username/1 deletes the ssh_username" do
      ssh_username = ssh_username_fixture()
      assert {:ok, %SshUsername{}} = Nodes.delete_ssh_username(ssh_username)
      assert_raise Ecto.NoResultsError, fn -> Nodes.get_ssh_username!(ssh_username.id) end
    end
  end

  describe "ssh_public_keys" do
    alias EdgeAdmin.Nodes.SshPublicKey

    @invalid_attrs %{public_key: nil, key_name: nil, ssh_username_id: nil}

    test "create_ssh_public_key/1 with valid data creates a ssh_public_key" do
      ssh_username = ssh_username_fixture()

      valid_attrs = %{
        public_key:
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 test@example.com",
        key_name: "laptop_key",
        ssh_username_id: ssh_username.id
      }

      assert {:ok, %SshPublicKey{} = ssh_public_key} = Nodes.create_ssh_public_key(valid_attrs)
      assert ssh_public_key.public_key == valid_attrs.public_key
      assert ssh_public_key.key_name == "laptop_key"
      assert ssh_public_key.ssh_username_id == ssh_username.id
    end

    test "create_ssh_public_key/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Nodes.create_ssh_public_key(@invalid_attrs)
    end

    test "create_ssh_public_key/1 enforces unique constraint per username" do
      ssh_username = ssh_username_fixture()

      attrs = %{
        public_key:
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 test@example.com",
        key_name: "laptop_key",
        ssh_username_id: ssh_username.id
      }

      # First creation should succeed
      assert {:ok, %SshPublicKey{}} = Nodes.create_ssh_public_key(attrs)

      # Second creation with same key_name + ssh_username should fail
      assert {:error, %Ecto.Changeset{} = changeset} = Nodes.create_ssh_public_key(attrs)
      assert changeset.errors[:key_name] != nil or changeset.errors[:ssh_username_id] != nil
    end

    test "delete_ssh_public_key/1 deletes the ssh_public_key" do
      ssh_public_key = ssh_public_key_fixture()
      assert {:ok, %SshPublicKey{}} = Nodes.delete_ssh_public_key(ssh_public_key)
      assert_raise Ecto.NoResultsError, fn -> Nodes.get_ssh_public_key!(ssh_public_key.id) end
    end

    test "list_ssh_public_keys_with_filtering_pagination basic functionality" do
      # Create test data
      ssh_username1 = ssh_username_fixture()
      ssh_username2 = ssh_username_fixture()
      _key1 = ssh_public_key_fixture(%{ssh_username_id: ssh_username1.id, key_name: "key1"})
      _key2 = ssh_public_key_fixture(%{ssh_username_id: ssh_username2.id, key_name: "key2"})

      # Test basic pagination
      result = Nodes.list_ssh_public_keys_with_filtering_pagination(%{})
      assert %EdgeAdmin.FilteringPagination{} = result
      assert length(result.data) == 2
      assert result.sort == [{:inserted_at, :desc}]

      # Test ssh_username_id filtering
      result =
        Nodes.list_ssh_public_keys_with_filtering_pagination(%{
          "ssh_username_id" => ssh_username1.id
        })

      assert length(result.data) == 1
      assert hd(result.data).ssh_username_id == ssh_username1.id

      # Test key_name filtering with wildcard
      result = Nodes.list_ssh_public_keys_with_filtering_pagination(%{"key_name" => "key1*"})
      assert length(result.data) == 1
      assert hd(result.data).key_name == "key1"
    end
  end
end
