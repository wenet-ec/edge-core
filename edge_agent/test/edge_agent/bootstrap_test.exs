# edge_agent/test/edge_agent/bootstrap_test.exs
defmodule EdgeAgent.BootstrapTest do
  use EdgeAgent.DataCase

  import Mox

  alias EdgeAgent.Bootstrap
  alias EdgeAgent.Settings.Setting

  # Mock modules
  defmock(VPNMock, for: EdgeAgent.VPN.Behaviour)
  defmock(AdminClientMock, for: EdgeAgent.AdminClientBehaviour)
  defmock(SshServerMock, for: EdgeAgent.SshServer.Behaviour)
  defmock(MetricsServerMock, for: EdgeAgent.MetricsServer.Behaviour)

  setup :verify_on_exit!

  setup do
    # Clear all settings before each test
    Repo.delete_all(Setting)
    :ok
  end

  describe "run/1 - success flow" do
    test "completes full bootstrap sequence successfully" do
      # Mock successful operations
      expect_successful_vpn_connection()
      expect_successful_admin_connection()
      expect_successful_ssh_server()
      expect_successful_metrics_server()

      opts = [
        vpn_module: VPNMock,
        admin_client_module: AdminClientMock,
        ssh_server_module: SshServerMock,
        metrics_server_module: MetricsServerMock
      ]

      assert {:ok, :bootstrap_complete} = Bootstrap.run(opts)
    end
  end

  describe "determine_node_identity/0" do
    test "returns machine_id when available" do
      # This tests the actual function without mocking file system
      # We'll implement a testable version that accepts file providers
      assert {:ok, _node_id, node_id_type} = Bootstrap.determine_node_identity()
      assert node_id_type in ["machine_id", "hardware_id", "temporary_id"]
    end
  end

  # Helper functions for setting up common mock expectations

  defp expect_successful_vpn_connection do
    expect(VPNMock, :start_daemon, fn -> :ok end)
    expect(VPNMock, :connect_to_vpn, fn _url, _key, _hostname -> {:ok, %{}} end)
    expect(VPNMock, :get_vpn_ip, fn -> {:ok, "100.64.0.10"} end)
    expect(VPNMock, :sync_connection_state, fn -> {:ok, %{}} end)
  end

  defp expect_successful_admin_connection do
    expect(AdminClientMock, :get_node, fn _node_id ->
      {:ok, %{"id" => "test-node", "status" => "online"}}
    end)
  end

  defp expect_successful_ssh_server do
    expect(SshServerMock, :start_server, fn -> :ok end)
  end

  defp expect_successful_metrics_server do
    expect(MetricsServerMock, :start_server, fn -> {:ok, :pid} end)
  end
end
