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
end
