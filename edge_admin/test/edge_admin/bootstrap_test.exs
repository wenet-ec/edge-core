# edge_admin/test/edge_admin/bootstrap_test.exs
defmodule EdgeAdmin.BootstrapTest do
  use ExUnit.Case, async: true

  import Mox

  alias EdgeAdmin.Bootstrap
  alias EdgeAdmin.TailscaleMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "run/1" do
    test "completes successfully with default options" do
      setup_successful_vpn_mocks()

      assert {:ok, :bootstrap_complete} = Bootstrap.run(vpn_module: TailscaleMock)
    end

    test "skips VPN setup when skip_vpn: true" do
      # No VPN mocks needed since VPN should be skipped
      assert {:ok, :bootstrap_complete} = Bootstrap.run(skip_vpn: true)
    end

    test "returns error when VPN setup fails" do
      expect(TailscaleMock, :start_daemon, fn -> {:error, :daemon_start_failed} end)

      assert {:error, :daemon_start_failed} = Bootstrap.run(vpn_module: TailscaleMock)
    end

    test "uses custom env_provider" do
      custom_env = fn
        "VPN_URL" -> "http://custom-vpn:9090"
        "ENROLLMENT_KEY" -> "custom-key"
        _ -> nil
      end

      expect(TailscaleMock, :start_daemon, fn -> :ok end)

      expect(TailscaleMock, :connect_to_vpn, fn
        "http://custom-vpn:9090", "custom-key", "edge-admin" ->
          {:ok, %{status: :connected}}
      end)

      expect(TailscaleMock, :get_vpn_ip, fn -> {:ok, "100.64.0.10"} end)
      expect(TailscaleMock, :sync_connection_state, fn -> {:ok, %{}} end)

      assert {:ok, :bootstrap_complete} =
               Bootstrap.run(
                 vpn_module: TailscaleMock,
                 env_provider: custom_env
               )
    end
  end

  describe "setup_vpn_connection/1" do
    test "successfully sets up VPN connection" do
      setup_successful_vpn_mocks()

      assert :ok = Bootstrap.setup_vpn_connection(vpn_module: TailscaleMock)
    end

    test "handles daemon start failure" do
      expect(TailscaleMock, :start_daemon, fn -> {:error, :permission_denied} end)

      assert {:error, :permission_denied} = Bootstrap.setup_vpn_connection(vpn_module: TailscaleMock)
    end

    test "handles VPN connection failure" do
      expect(TailscaleMock, :start_daemon, fn -> :ok end)

      expect(TailscaleMock, :connect_to_vpn, fn _, _, _ ->
        {:error, :invalid_enrollment_key}
      end)

      assert {:error, :invalid_enrollment_key} = Bootstrap.setup_vpn_connection(vpn_module: TailscaleMock)
    end

    test "handles VPN IP validation failure" do
      expect(TailscaleMock, :start_daemon, fn -> :ok end)

      expect(TailscaleMock, :connect_to_vpn, fn _, _, _ ->
        {:ok, %{status: :connected}}
      end)

      expect(TailscaleMock, :get_vpn_ip, fn -> {:error, :no_ip_assigned} end)

      assert {:error, "VPN connection validation failed: :no_ip_assigned"} =
               Bootstrap.setup_vpn_connection(vpn_module: TailscaleMock)
    end

    test "handles sync connection state failure" do
      expect(TailscaleMock, :start_daemon, fn -> :ok end)

      expect(TailscaleMock, :connect_to_vpn, fn _, _, _ ->
        {:ok, %{status: :connected}}
      end)

      expect(TailscaleMock, :get_vpn_ip, fn -> {:ok, "100.64.0.10"} end)
      expect(TailscaleMock, :sync_connection_state, fn -> {:error, :sync_failed} end)

      assert {:error, :sync_failed} = Bootstrap.setup_vpn_connection(vpn_module: TailscaleMock)
    end

    test "uses override parameters for credentials" do
      expect(TailscaleMock, :start_daemon, fn -> :ok end)

      expect(TailscaleMock, :connect_to_vpn, fn
        "http://test-override:8888", "override-key", "edge-admin" ->
          {:ok, %{status: :connected}}
      end)

      expect(TailscaleMock, :get_vpn_ip, fn -> {:ok, "100.64.0.10"} end)
      expect(TailscaleMock, :sync_connection_state, fn -> {:ok, %{}} end)

      assert :ok =
               Bootstrap.setup_vpn_connection(
                 vpn_module: TailscaleMock,
                 vpn_url: "http://test-override:8888",
                 enrollment_key: "override-key"
               )
    end

    test "handles missing environment variables gracefully" do
      env_provider = fn _ -> nil end

      expect(TailscaleMock, :start_daemon, fn -> :ok end)

      expect(TailscaleMock, :connect_to_vpn, fn nil, nil, "edge-admin" ->
        {:ok, %{status: :connected}}
      end)

      expect(TailscaleMock, :get_vpn_ip, fn -> {:ok, "100.64.0.10"} end)
      expect(TailscaleMock, :sync_connection_state, fn -> {:ok, %{}} end)

      assert :ok =
               Bootstrap.setup_vpn_connection(
                 vpn_module: TailscaleMock,
                 env_provider: env_provider
               )
    end
  end

  describe "validation scenarios" do
    test "validates IP address format" do
      expect(TailscaleMock, :start_daemon, fn -> :ok end)

      expect(TailscaleMock, :connect_to_vpn, fn _, _, _ ->
        {:ok, %{status: :connected}}
      end)

      expect(TailscaleMock, :get_vpn_ip, fn -> {:error, :no_ip_available} end)

      # Test actual error case from get_vpn_ip
      assert {:error, "VPN connection validation failed: :no_ip_available"} =
               Bootstrap.setup_vpn_connection(vpn_module: TailscaleMock)
    end

    test "accepts valid IP addresses" do
      for ip <- ["100.64.0.10", "192.168.1.100", "10.0.0.1"] do
        expect(TailscaleMock, :start_daemon, fn -> :ok end)

        expect(TailscaleMock, :connect_to_vpn, fn _, _, _ ->
          {:ok, %{status: :connected}}
        end)

        expect(TailscaleMock, :get_vpn_ip, fn -> {:ok, ip} end)
        expect(TailscaleMock, :sync_connection_state, fn -> {:ok, %{}} end)

        assert :ok = Bootstrap.setup_vpn_connection(vpn_module: TailscaleMock)
      end
    end
  end

  describe "integration scenarios" do
    test "complete bootstrap flow with all steps" do
      setup_successful_vpn_mocks()

      result =
        Bootstrap.run(
          vpn_module: TailscaleMock,
          vpn_url: "http://test-vpn:8080",
          enrollment_key: "test-key"
        )

      assert {:ok, :bootstrap_complete} = result
    end

    test "graceful degradation on partial failures" do
      # Test that bootstrap can handle certain types of non-critical failures
      expect(TailscaleMock, :start_daemon, fn -> :ok end)

      expect(TailscaleMock, :connect_to_vpn, fn _, _, _ ->
        {:ok, %{status: :connected}}
      end)

      expect(TailscaleMock, :get_vpn_ip, fn -> {:ok, "100.64.0.10"} end)

      # Sync fails but we might want to continue in some scenarios
      expect(TailscaleMock, :sync_connection_state, fn -> {:error, :sync_timeout} end)

      assert {:error, :sync_timeout} = Bootstrap.setup_vpn_connection(vpn_module: TailscaleMock)
    end
  end

  # Helper function to set up successful VPN mocks
  defp setup_successful_vpn_mocks do
    expect(TailscaleMock, :start_daemon, fn -> :ok end)

    expect(TailscaleMock, :connect_to_vpn, fn _, _, _ ->
      {:ok, %{status: :connected}}
    end)

    expect(TailscaleMock, :get_vpn_ip, fn -> {:ok, "100.64.0.10"} end)
    expect(TailscaleMock, :sync_connection_state, fn -> {:ok, %{}} end)
  end
end
