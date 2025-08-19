# edge_agent/test/edge_agent/vpn_test.exs
defmodule EdgeAgent.VPNTest do
  use EdgeAgent.DataCase
  import Mox

  alias EdgeAgent.VPN
  alias EdgeAgent.Settings.Setting

  # Mock the Tailscale module
  defmock(TailscaleMock, for: TailscaleBehaviour)

  setup :verify_on_exit!

  setup do
    # Clear all settings before each test
    Repo.delete_all(Setting)
    # Configure mock for VPN module
    Application.put_env(:edge_agent, :tailscale_module, TailscaleMock)
    :ok
  end

  describe "delegation functions" do
    test "start_daemon/0 delegates to Tailscale" do
      expect(TailscaleMock, :start_daemon, fn -> :ok end)
      assert :ok = VPN.start_daemon()
    end

    test "connect_to_vpn/3 delegates to Tailscale" do
      expect(TailscaleMock, :connect_to_vpn, fn url, key, hostname ->
        assert url == "test-url"
        assert key == "test-key" 
        assert hostname == "test-hostname"
        {:ok, %{}}
      end)
      
      assert {:ok, %{}} = VPN.connect_to_vpn("test-url", "test-key", "test-hostname")
    end

    test "get_vpn_ip/0 delegates to Tailscale" do
      expect(TailscaleMock, :get_vpn_ip, fn -> {:ok, "100.64.0.10"} end)
      assert {:ok, "100.64.0.10"} = VPN.get_vpn_ip()
    end

    test "check_connectivity/0 delegates to Tailscale" do
      expect(TailscaleMock, :check_connectivity, fn -> {:ok, :connected} end)
      assert {:ok, :connected} = VPN.check_connectivity()
    end
  end

  describe "EdgeAgent-specific business logic" do
    test "update_connection/1 gets connection and delegates update" do
      connection = %{id: "conn-1", status: "disconnected"}
      attrs = %{status: "connected"}
      
      expect(TailscaleMock, :get_connection!, fn -> connection end)
      expect(TailscaleMock, :update_connection, fn conn, update_attrs ->
        assert conn == connection
        assert update_attrs == attrs
        {:ok, %{connection | status: "connected"}}
      end)
      
      assert {:ok, _} = VPN.update_connection(attrs)
    end
  end

  describe "environment variable handling" do
    test "vpn_url raises when VPN_URL not set" do
      # Remove env var
      System.delete_env("VPN_URL")
      
      assert_raise RuntimeError, "VPN_URL environment variable not set", fn ->
        VPN.attempt_auto_reconnection()
      end
    end

    test "enrollment_key raises when ENROLLMENT_KEY not set" do
      # Set VPN_URL but not ENROLLMENT_KEY
      System.put_env("VPN_URL", "test-url")
      System.delete_env("ENROLLMENT_KEY")
      
      assert_raise RuntimeError, "ENROLLMENT_KEY environment variable not set", fn ->
        VPN.attempt_auto_reconnection()
      end
    end
  end
end