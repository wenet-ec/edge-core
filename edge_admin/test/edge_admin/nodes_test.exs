# edge_admin/test/edge_admin/nodes_test.exs
defmodule EdgeAdmin.NodesTest do
  use EdgeAdmin.DataCase

  import EdgeAdmin.NodesFixtures

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Node
  alias EdgeAdmin.Nodes.SshUsername

  describe "node CRUD operations" do
    test "get_node!/1 returns node with virtual fields" do
      node = node_fixture()
      fetched = Nodes.get_node!(node.id)
      assert fetched.id == node.id
      # Virtual field populated
      assert fetched.vpn_hostname
    end

    test "update_node/2 with valid data updates the node" do
      node = node_fixture()
      update_attrs = %{status: "offline", vpn_ip: "100.64.0.99"}

      assert {:ok, updated_node} = Nodes.update_node(node, update_attrs)
      assert updated_node.status == "offline"
      assert updated_node.vpn_ip == "100.64.0.99"
    end

    test "delete_node/1 deletes the node" do
      node = node_fixture()
      assert {:ok, _} = Nodes.delete_node(node)
      assert_raise Ecto.NoResultsError, fn -> Nodes.get_node!(node.id) end
    end

    test "change_node/1 returns a node changeset" do
      node = node_fixture()
      changeset = Nodes.change_node(node)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "node filtering and pagination" do
    test "list_nodes_with_filtering_pagination returns paginated results" do
      _node1 = node_fixture(%{status: "online"})
      _node2 = node_fixture(%{status: "offline"})

      result = Nodes.list_nodes_with_filtering_pagination(%{})
      assert length(result.data) >= 2
      assert result.page == 1
    end

    test "filters nodes by status" do
      _online_node = node_fixture(%{status: "online"})
      _offline_node = node_fixture(%{status: "offline"})

      result = Nodes.list_nodes_with_filtering_pagination(%{"status" => "online"})

      # Should only return online nodes
      Enum.each(result.data, fn node ->
        assert node.status == "online"
      end)
    end

    test "sorts nodes by specified field" do
      _node1 = node_fixture(%{status: "offline"})
      _node2 = node_fixture(%{status: "online"})

      result =
        Nodes.list_nodes_with_filtering_pagination(%{
          "sort" => "status:asc",
          "page_size" => "10"
        })

      statuses = result.data |> Enum.map(& &1.status) |> Enum.filter(&(&1 != nil))

      if length(statuses) >= 2 do
        assert List.first(statuses) <= List.last(statuses)
      end
    end
  end

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
      assert changeset.errors[:id_type]
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

  describe "node metrics" do
    test "list_node_metrics/1 returns node_not_found for invalid node ID" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :node_not_found} = Nodes.list_node_metrics(fake_id)
    end

    test "list_node_metrics/1 returns metrics_unavailable when node has no VPN IP" do
      {:ok, node} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "machine_id",
          vpn_ip: nil
        })

      assert {:error, :metrics_unavailable} = Nodes.list_node_metrics(node.id)
    end

    test "list_node_metrics/1 returns metrics_unavailable when node has empty VPN IP" do
      {:ok, node} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "machine_id",
          vpn_ip: ""
        })

      assert {:error, :metrics_unavailable} = Nodes.list_node_metrics(node.id)
    end

    test "list_node_metrics/1 returns metrics_unavailable when metrics storage URL is missing" do
      {:ok, node} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "machine_id",
          vpn_ip: "100.64.0.1"
        })

      # Remove the config entirely
      original_url = Application.get_env(:edge_admin, :metrics_storage_url)
      Application.delete_env(:edge_admin, :metrics_storage_url)

      try do
        assert {:error, :metrics_unavailable} = Nodes.list_node_metrics(node.id)
      after
        Application.put_env(:edge_admin, :metrics_storage_url, original_url)
      end
    end

    test "list_node_metrics/1 returns metrics_unavailable when metrics storage URL is empty" do
      {:ok, node} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "machine_id",
          vpn_ip: "100.64.0.1"
        })

      # Set empty config
      original_url = Application.get_env(:edge_admin, :metrics_storage_url)
      Application.put_env(:edge_admin, :metrics_storage_url, "")

      try do
        assert {:error, :metrics_unavailable} = Nodes.list_node_metrics(node.id)
      after
        Application.put_env(:edge_admin, :metrics_storage_url, original_url)
      end
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
        public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 test@example.com",
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
        public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 test@example.com",
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

    test "validates SSH public key format and algorithms" do
      ssh_username = ssh_username_fixture()

      # Valid Ed25519 keys (easier to test with)
      valid_keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@host",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7f6E+VW7k3q3Q8Q2Q2Q2Q2Q2Q2Q2Q2Q2Q2Q2Q2Q2Q2 test@laptop"
      ]

      for {valid_key, index} <- Enum.with_index(valid_keys) do
        attrs = %{
          public_key: valid_key,
          key_name: "test-key-#{index}",
          ssh_username_id: ssh_username.id
        }

        assert {:ok, _} = Nodes.create_ssh_public_key(attrs)
      end

      # Test that different algorithms are detected correctly
      algorithm_tests = [
        {"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8", "ssh-ed25519"}
        # You can add more when you have valid test keys for other algorithms
      ]

      for {key, expected_algorithm} <- algorithm_tests do
        assert {:ok, ^expected_algorithm} = SshPublicKey.validate_key_format(key)
      end

      # Invalid keys should fail validation
      invalid_keys = [
        # Completely invalid format
        "not-a-ssh-key",
        # Missing key data
        "ssh-ed25519",
        # Invalid base64
        "ssh-ed25519 invalid-base64!@#$%",
        # Unsupported algorithm
        "ssh-unknown AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8",
        # Empty string
        "",
        # Only whitespace
        "   \n\t  "
      ]

      for {invalid_key, index} <- Enum.with_index(invalid_keys) do
        attrs = %{
          public_key: invalid_key,
          key_name: "invalid-key-#{index}",
          ssh_username_id: ssh_username.id
        }

        assert {:error, %Ecto.Changeset{} = changeset} = Nodes.create_ssh_public_key(attrs)
        assert changeset.errors[:public_key]
      end
    end

    test "SshPublicKey.validate_key_format/1 utility function" do
      # Test the utility function directly
      assert {:ok, "ssh-ed25519"} =
               SshPublicKey.validate_key_format(
                 "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8"
               )

      assert {:error, _} = SshPublicKey.validate_key_format("invalid-key")
    end
  end

  describe "metrics discovery" do
    test "list_metrics_discovery_targets returns empty list when no nodes exist" do
      # Ensure no nodes exist
      assert Nodes.list_metrics_discovery_targets() == []
    end

    test "list_metrics_discovery_targets returns empty list when nodes have no VPN IPs" do
      # Create nodes without VPN IPs
      {:ok, _node1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "machine_id", vpn_ip: nil})

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", vpn_ip: ""})

      assert Nodes.list_metrics_discovery_targets() == []
    end

    test "list_metrics_discovery_targets returns formatted targets for nodes with VPN IPs" do
      # Create nodes with VPN IPs
      {:ok, _node1} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "machine_id",
          vpn_ip: "100.64.0.1"
        })

      {:ok, _node2} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "hardware_id",
          vpn_ip: "100.64.0.2"
        })

      targets = Nodes.list_metrics_discovery_targets()

      assert length(targets) == 2
      assert "100.64.0.1:9100" in targets
      assert "100.64.0.2:9100" in targets

      # Verify all targets have the :9100 port suffix
      Enum.each(targets, fn target ->
        assert String.ends_with?(target, ":9100")
      end)
    end

    test "list_metrics_discovery_targets only includes nodes with valid VPN IPs" do
      # Create mix of nodes
      {:ok, _valid1} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "machine_id",
          vpn_ip: "100.64.0.10"
        })

      {:ok, _invalid1} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", vpn_ip: nil})

      {:ok, _invalid2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "temporary_id", vpn_ip: ""})

      {:ok, _valid2} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "machine_id",
          vpn_ip: "100.64.0.20"
        })

      targets = Nodes.list_metrics_discovery_targets()

      # Should only include the 2 nodes with valid VPN IPs
      assert length(targets) == 2
      assert "100.64.0.10:9100" in targets
      assert "100.64.0.20:9100" in targets
    end

    test "list_metrics_discovery_targets handles various VPN IP formats" do
      # Test different valid IP formats that might be in the database
      {:ok, _node1} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "machine_id",
          vpn_ip: "192.168.1.100"
        })

      {:ok, _node2} =
        Nodes.create_node(%{id: Ecto.UUID.generate(), id_type: "hardware_id", vpn_ip: "10.0.0.5"})

      {:ok, _node3} =
        Nodes.create_node(%{
          id: Ecto.UUID.generate(),
          id_type: "temporary_id",
          vpn_ip: "172.16.0.1"
        })

      targets = Nodes.list_metrics_discovery_targets()

      assert length(targets) == 3
      assert "192.168.1.100:9100" in targets
      assert "10.0.0.5:9100" in targets
      assert "172.16.0.1:9100" in targets
    end
  end

  describe "cluster CRUD operations" do
    test "list_clusters/0 returns all clusters with node counts" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      clusters = Nodes.list_clusters()
      assert length(clusters) >= 1
      assert Enum.any?(clusters, fn c -> c.id == cluster.id end)

      # Check node_count is present
      found_cluster = Enum.find(clusters, fn c -> c.id == cluster.id end)
      assert found_cluster.node_count == 0
    end

    test "list_clusters_with_filtering_pagination/1 filters and paginates" do
      expect(NexmakerMock, :create_network, 2, fn _, _ -> {:ok, %{}} end)

      cluster1 = cluster_fixture(%{ipv4_range: "100.64.1.0/24"})
      _cluster2 = cluster_fixture(%{ipv4_range: "100.64.2.0/24"})

      # Filter by ipv4_range
      result = Nodes.list_clusters_with_filtering_pagination(%{"ipv4_range" => "100.64.1"})
      assert length(result.data) == 1
      assert hd(result.data).id == cluster1.id
      assert result.total == 1

      # No filter returns all with pagination
      result = Nodes.list_clusters_with_filtering_pagination(%{})
      assert length(result.data) >= 2
      assert result.pagination == %{}
      assert result.total >= 2
    end

    test "list_clusters_with_filtering_pagination/1 supports sorting" do
      expect(NexmakerMock, :create_network, 2, fn _, _ -> {:ok, %{}} end)

      cluster1 = cluster_fixture(%{ipv4_range: "100.64.1.0/24"})
      cluster2 = cluster_fixture(%{ipv4_range: "100.64.2.0/24"})

      # Sort by ipv4_range ascending
      result = Nodes.list_clusters_with_filtering_pagination(%{"sort" => "ipv4_range:asc"})
      assert hd(result.data).id == cluster1.id
      assert result.sort == [{:ipv4_range, :asc}]
    end

    test "get_cluster!/1 returns the cluster with node count" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      fetched = Nodes.get_cluster!(cluster.id)
      assert fetched.id == cluster.id
      assert fetched.node_count == 0
    end

    test "create_cluster/1 with valid data creates a cluster and Netmaker network" do
      expect(NexmakerMock, :create_network, fn network_name, params ->
        assert network_name =~ ~r/^cluster-/
        assert params.addressrange == "100.64.50.0/24"
        {:ok, %{}}
      end)

      assert {:ok, %Cluster{} = cluster} =
               Nodes.create_cluster(%{ipv4_range: "100.64.50.0/24"})

      assert cluster.ipv4_range == "100.64.50.0/24"
      assert cluster.id
    end

    test "create_cluster/1 with explicit ID creates cluster with that ID" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)

      explicit_id = Ecto.UUID.generate()

      assert {:ok, %Cluster{} = cluster} =
               Nodes.create_cluster(%{id: explicit_id, ipv4_range: "100.64.51.0/24"})

      assert cluster.id == explicit_id
    end

    test "create_cluster/1 auto-generates IP range if not provided" do
      expect(NexmakerMock, :create_network, fn _, params ->
        assert params.addressrange =~ ~r/^100\.64\.\d+\.0\/24$/
        {:ok, %{}}
      end)

      assert {:ok, %Cluster{} = cluster} = Nodes.create_cluster(%{})
      assert cluster.ipv4_range =~ ~r/^100\.64\.\d+\.0\/24$/
    end

    test "create_cluster/1 rolls back on Netmaker network creation failure" do
      expect(NexmakerMock, :create_network, fn _, _ ->
        {:error, "Netmaker error"}
      end)

      assert {:error, "Netmaker error"} = Nodes.create_cluster(%{ipv4_range: "100.64.52.0/24"})

      # Cluster should not exist in database
      assert Nodes.list_clusters() == []
    end

    test "create_cluster/1 with invalid ipv4_range returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Nodes.create_cluster(%{ipv4_range: "invalid"})
    end

    test "create_cluster/1 with duplicate ipv4_range returns error" do
      expect(NexmakerMock, :create_network, 2, fn _, _ -> {:ok, %{}} end)

      {:ok, _cluster1} = Nodes.create_cluster(%{ipv4_range: "100.64.60.0/24"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Nodes.create_cluster(%{ipv4_range: "100.64.60.0/24"})

      assert changeset.errors[:ipv4_range]
    end

    test "delete_cluster/1 deletes the cluster and Netmaker network" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)

      expect(NexmakerMock, :delete_network, fn network_name ->
        assert network_name =~ ~r/^cluster-/
        {:ok, %{}}
      end)

      cluster = cluster_fixture()
      assert {:ok, %Cluster{}} = Nodes.delete_cluster(cluster)
      assert_raise Ecto.NoResultsError, fn -> Nodes.get_cluster!(cluster.id) end
    end

    test "delete_cluster/1 rolls back on Netmaker network deletion failure" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)

      expect(NexmakerMock, :delete_network, fn _ ->
        {:error, "Netmaker deletion error"}
      end)

      cluster = cluster_fixture()
      assert {:error, "Netmaker deletion error"} = Nodes.delete_cluster(cluster)

      # Cluster should still exist in database
      assert Nodes.get_cluster!(cluster.id)
    end

    test "change_cluster/1 returns a cluster changeset" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      changeset = Nodes.change_cluster(cluster)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "IP range validation" do
    test "rejects private ranges" do
      assert {:error, changeset} = Nodes.create_cluster(%{ipv4_range: "192.168.1.0/24"})
      assert changeset.errors[:ipv4_range]
    end

    test "rejects loopback range" do
      assert {:error, changeset} = Nodes.create_cluster(%{ipv4_range: "127.0.0.0/8"})
      assert changeset.errors[:ipv4_range]
    end

    test "rejects link-local range" do
      assert {:error, changeset} = Nodes.create_cluster(%{ipv4_range: "169.254.0.0/16"})
      assert changeset.errors[:ipv4_range]
    end

    test "accepts valid CGNAT range (100.64.0.0/10)" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)

      assert {:ok, cluster} = Nodes.create_cluster(%{ipv4_range: "100.64.100.0/24"})
      assert cluster.ipv4_range == "100.64.100.0/24"
    end
  end

  describe "Cluster helper functions" do
    test "network_name/1 returns correct format" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      assert Cluster.network_name(cluster) == "cluster-#{cluster.id}"
    end

    test "dns_domain/1 returns correct format" do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      assert Cluster.dns_domain(cluster) == "cluster-#{cluster.id}.nm.internal"
    end
  end
end
