defmodule EdgeAdmin.ProxyServers.AuthenticationTest do
  use ExUnit.Case, async: true

  import Mox

  alias EdgeAdmin.ProxyServers.Authentication

  setup :verify_on_exit!

  describe "authenticate_and_parse/2 - direct mode" do
    test "authenticates with underscore username for direct VPN access" do
      # AUTH_ENABLED=false in test env, so any password works
      assert {:ok, :direct} = Authentication.authenticate_and_parse("_", "any_password")
    end

    test "authenticates with empty username for direct VPN access" do
      assert {:ok, :direct} = Authentication.authenticate_and_parse("", "any_password")
    end
  end

  describe "authenticate_and_parse/2 - chain mode with valid node" do
    test "parses valid node DNS hostname and returns chain mode" do
      # Create a mock node struct
      mock_node = %{
        id: "abc123",
        dns_hostname: "node-abc123.cluster-prod.nm.internal",
        cluster_id: "cluster-123"
      }

      # Mock the Nodes.list_node_identifiers_by_cluster call
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "prod" ->
        {:ok, %{"abc123" => mock_node}}
      end)

      result = Authentication.authenticate_and_parse("node-abc123.cluster-prod.nm.internal", "any_password")

      assert {:ok, :chain, returned_node} = result
      assert returned_node.id == "abc123"
    end

    test "handles node lookup by alias" do
      mock_node = %{
        id: "node-123",
        dns_hostname: "node-123.cluster-staging.nm.internal"
      }

      # Mock returns node by alias name
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "staging" ->
        {:ok,
         %{
           "node-123" => mock_node,
           # alias points to same node
           "web-server" => mock_node
         }}
      end)

      result = Authentication.authenticate_and_parse("node-web-server.cluster-staging.nm.internal", "any_password")

      assert {:ok, :chain, returned_node} = result
      assert returned_node.id == "node-123"
    end

    test "handles multiple nodes in cluster" do
      node1 = %{id: "node-1", dns_hostname: "node-1.cluster-prod.nm.internal"}
      node2 = %{id: "node-2", dns_hostname: "node-2.cluster-prod.nm.internal"}

      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "prod" ->
        {:ok,
         %{
           "1" => node1,
           "2" => node2
         }}
      end)

      result = Authentication.authenticate_and_parse("node-2.cluster-prod.nm.internal", "any_password")

      assert {:ok, :chain, returned_node} = result
      assert returned_node.id == "node-2"
    end
  end

  describe "authenticate_and_parse/2 - chain mode errors" do
    test "returns error when node not found in cluster" do
      # Mock returns empty map (no nodes with that identifier)
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "dev" ->
        {:ok, %{"other-node" => %{id: "other-node"}}}
      end)

      result = Authentication.authenticate_and_parse("node-nonexistent.cluster-dev.nm.internal", "any_password")

      assert {:error, :node_not_found} = result
    end

    test "returns error when cluster not found" do
      # Mock returns cluster not found error
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "nonexistent" ->
        {:error, :not_found}
      end)

      result = Authentication.authenticate_and_parse("node-abc.cluster-nonexistent.nm.internal", "any_password")

      assert {:error, :cluster_not_found} = result
    end

    test "returns error for invalid DNS format" do
      # No mock needed - invalid format doesn't reach DB call
      result = Authentication.authenticate_and_parse("invalid-hostname", "any_password")

      assert {:error, :invalid_dns_format} = result
    end

    test "returns error for DNS format without proper structure" do
      result = Authentication.authenticate_and_parse("just-text", "any_password")

      assert {:error, :invalid_dns_format} = result
    end
  end

  describe "DNS parsing logic" do
    test "correctly extracts cluster name from DNS hostname" do
      mock_node = %{id: "test-node"}

      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn cluster_name ->
        # Verify cluster name is extracted correctly (without "cluster-" prefix)
        assert cluster_name == "production"
        {:ok, %{"xyz" => mock_node}}
      end)

      result = Authentication.authenticate_and_parse("node-xyz.cluster-production.nm.internal", "any_password")

      assert {:ok, :chain, _} = result
    end

    test "handles cluster names with hyphens" do
      mock_node = %{id: "node-1"}

      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn cluster_name ->
        assert cluster_name == "my-cluster-name"
        {:ok, %{"123" => mock_node}}
      end)

      result = Authentication.authenticate_and_parse("node-123.cluster-my-cluster-name.nm.internal", "any_password")

      assert {:ok, :chain, _} = result
    end

    test "empty string routes to direct mode without DB call" do
      # No mock expectation - should not call DB
      assert {:ok, :direct} = Authentication.authenticate_and_parse("", "any_password")
    end

    test "underscore routes to direct mode without DB call" do
      # No mock expectation - should not call DB
      assert {:ok, :direct} = Authentication.authenticate_and_parse("_", "any_password")
    end
  end
end
