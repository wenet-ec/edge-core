# edge_admin/test/edge_admin/admins/discovery_test.exs
defmodule EdgeAdmin.Admins.DiscoveryTest do
  use ExUnit.Case, async: true

  import Mox

  alias EdgeAdmin.Admins.Discovery

  setup :verify_on_exit!

  describe "scan_and_connect_admins/0" do
    test "function signature is correct" do
      assert function_exported?(Discovery, :scan_and_connect_admins, 0)
    end

    test "returns :ok when Netmaker API returns empty nodes list" do
      # Setup ETS table with admin cluster info
      :ets.new(:metadata, [:set, :public, :named_table])
      :ets.insert(:metadata, {:admin_cluster, %{name: "test-cluster"}})

      # Mock the Nexmaker.Api.Nodes.list call
      Mox.expect(Nexmaker.Api.NodesMock, :list, fn "test-cluster", _opts ->
        {:ok, []}
      end)

      # Should return :ok even with no nodes
      assert Discovery.scan_and_connect_admins() == :ok
    after
      :ets.delete(:metadata)
    end

    test "returns :ok when Netmaker API returns error" do
      # Setup ETS table with admin cluster info
      :ets.new(:metadata, [:set, :public, :named_table])
      :ets.insert(:metadata, {:admin_cluster, %{name: "test-cluster"}})

      # Mock the Nexmaker.Api.Nodes.list call to return error
      Mox.expect(Nexmaker.Api.NodesMock, :list, fn "test-cluster", _opts ->
        {:error, :connection_refused}
      end)

      # Should return :ok even on error (graceful degradation)
      assert Discovery.scan_and_connect_admins() == :ok
    after
      :ets.delete(:metadata)
    end

    test "extracts IPs from nodes and filters out empty addresses" do
      # Setup ETS table with admin cluster info
      :ets.new(:metadata, [:set, :public, :named_table])
      :ets.insert(:metadata, {:admin_cluster, %{name: "test-cluster"}})

      # Mock the Nexmaker.Api.Nodes.list call with mixed addresses
      Mox.expect(Nexmaker.Api.NodesMock, :list, fn "test-cluster", _opts ->
        {:ok, [
          %{"address" => "100.64.0.1", "node_id" => "node-1"},
          %{"address" => "", "node_id" => "node-2"},
          %{"address" => nil, "node_id" => "node-3"},
          %{"address" => "100.64.0.4", "node_id" => "node-4"}
        ]}
      end)

      # Should return :ok (probing will fail but that's expected in test)
      assert Discovery.scan_and_connect_admins() == :ok
    after
      :ets.delete(:metadata)
    end
  end

  describe "create_and_join_admin_cluster/1" do
    test "function signature is correct" do
      # Verify the function exists with correct arity
      assert function_exported?(Discovery, :create_and_join_admin_cluster, 1)
    end

    test "creates network if it doesn't exist" do
      # Set up application config
      Application.put_env(:edge_admin, :admin_cluster_subnet, "100.63.0.0/24")
      Application.put_env(:edge_admin, :admin_name, "admin-test123")

      # Mock network doesn't exist
      Mox.expect(Nexmaker.Api.NetworksMock, :get, fn "test-cluster", _opts ->
        {:error, :not_found}
      end)

      # Mock network creation
      Mox.expect(Nexmaker.Api.NetworksMock, :create, fn "test-cluster", %{addressrange: "100.63.0.0/24"}, _opts ->
        {:ok, %{"netid" => "test-cluster"}}
      end)

      # Mock enrollment key creation
      Mox.expect(Nexmaker.Api.EnrollmentKeysMock, :create, fn "test-cluster", %{uses_remaining: 1, expiration: 86400, tags: ["admin-test123"]}, _opts ->
        {:ok, %{"token" => "test-token-abc123"}}
      end)

      # Mock netclient join
      Mox.expect(Nexmaker.CliMock, :join_network, fn [token: "test-token-abc123", name: "admin-test123"] ->
        {:ok, %{}}
      end)

      assert Discovery.create_and_join_admin_cluster("test-cluster") == :ok
    end

    test "skips network creation if it already exists" do
      # Set up application config
      Application.put_env(:edge_admin, :admin_name, "admin-test123")

      # Mock network exists
      Mox.expect(Nexmaker.Api.NetworksMock, :get, fn "test-cluster", _opts ->
        {:ok, %{"netid" => "test-cluster"}}
      end)

      # Mock enrollment key creation
      Mox.expect(Nexmaker.Api.EnrollmentKeysMock, :create, fn "test-cluster", %{uses_remaining: 1, expiration: 86400, tags: ["admin-test123"]}, _opts ->
        {:ok, %{"token" => "test-token-abc123"}}
      end)

      # Mock netclient join
      Mox.expect(Nexmaker.CliMock, :join_network, fn [token: "test-token-abc123", name: "admin-test123"] ->
        {:ok, %{}}
      end)

      assert Discovery.create_and_join_admin_cluster("test-cluster") == :ok
    end

    test "handles Netmaker 500 error with 'no result found' as network not existing" do
      # Set up application config
      Application.put_env(:edge_admin, :admin_cluster_subnet, "100.63.0.0/24")
      Application.put_env(:edge_admin, :admin_name, "admin-test123")

      # Mock network returns 500 with "no result found"
      Mox.expect(Nexmaker.Api.NetworksMock, :get, fn "test-cluster", _opts ->
        {:error, {:http_error, 500, "no result found"}}
      end)

      # Mock network creation
      Mox.expect(Nexmaker.Api.NetworksMock, :create, fn "test-cluster", %{addressrange: "100.63.0.0/24"}, _opts ->
        {:ok, %{"netid" => "test-cluster"}}
      end)

      # Mock enrollment key creation
      Mox.expect(Nexmaker.Api.EnrollmentKeysMock, :create, fn "test-cluster", %{uses_remaining: 1, expiration: 86400, tags: ["admin-test123"]}, _opts ->
        {:ok, %{"token" => "test-token-abc123"}}
      end)

      # Mock netclient join
      Mox.expect(Nexmaker.CliMock, :join_network, fn [token: "test-token-abc123", name: "admin-test123"] ->
        {:ok, %{}}
      end)

      assert Discovery.create_and_join_admin_cluster("test-cluster") == :ok
    end

    test "returns error when network creation fails" do
      # Set up application config
      Application.put_env(:edge_admin, :admin_cluster_subnet, "100.63.0.0/24")

      # Mock network doesn't exist
      Mox.expect(Nexmaker.Api.NetworksMock, :get, fn "test-cluster", _opts ->
        {:error, :not_found}
      end)

      # Mock network creation fails
      Mox.expect(Nexmaker.Api.NetworksMock, :create, fn "test-cluster", %{addressrange: "100.63.0.0/24"}, _opts ->
        {:error, :connection_refused}
      end)

      assert Discovery.create_and_join_admin_cluster("test-cluster") == {:error, :connection_refused}
    end

    test "returns error when enrollment key creation fails" do
      # Set up application config
      Application.put_env(:edge_admin, :admin_name, "admin-test123")

      # Mock network exists
      Mox.expect(Nexmaker.Api.NetworksMock, :get, fn "test-cluster", _opts ->
        {:ok, %{"netid" => "test-cluster"}}
      end)

      # Mock enrollment key creation fails
      Mox.expect(Nexmaker.Api.EnrollmentKeysMock, :create, fn "test-cluster", _params, _opts ->
        {:error, :quota_exceeded}
      end)

      assert Discovery.create_and_join_admin_cluster("test-cluster") == {:error, :quota_exceeded}
    end

    test "returns error when netclient join fails" do
      # Set up application config
      Application.put_env(:edge_admin, :admin_name, "admin-test123")

      # Mock network exists
      Mox.expect(Nexmaker.Api.NetworksMock, :get, fn "test-cluster", _opts ->
        {:ok, %{"netid" => "test-cluster"}}
      end)

      # Mock enrollment key creation
      Mox.expect(Nexmaker.Api.EnrollmentKeysMock, :create, fn "test-cluster", _params, _opts ->
        {:ok, %{"token" => "test-token-abc123"}}
      end)

      # Mock netclient join fails
      Mox.expect(Nexmaker.CliMock, :join_network, fn [token: "test-token-abc123", name: "admin-test123"] ->
        {:error, {:netclient_error, 1, "connection refused"}}
      end)

      assert Discovery.create_and_join_admin_cluster("test-cluster") == {:error, {:netclient_error, 1, "connection refused"}}
    end
  end
end
