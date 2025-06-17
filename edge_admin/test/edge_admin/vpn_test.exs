# edge_admin/test/edge_admin/vpn_test.exs
defmodule EdgeAdmin.VPNTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.VPN

  import Mox

  # Setup mock for Tailscale
  defmock(EdgeAdmin.TailscaleMock, for: EdgeAdmin.Tailscale.Behaviour)

  setup do
    # Reset the ETS table state between tests
    :ets.delete_all_objects(:vpn_connection)
    {:ok, _} = VPN.create_connection(%{})

    # Replace Tailscale with mock
    Application.put_env(:edge_admin, :tailscale_module, EdgeAdmin.TailscaleMock)

    on_exit(fn ->
      # Restore original module
      Application.put_env(:edge_admin, :tailscale_module, EdgeAdmin.Tailscale)
    end)

    :ok
  end

  describe "state management (CRUD)" do
    test "get_connection/0 returns the connection" do
      assert {:ok, connection} = VPN.get_connection()
      assert connection.status == :disconnected
      assert connection.manual_disconnect == false
    end

    test "update_connection/1 updates connection state" do
      attrs = %{status: :connected, vpn_ip: "100.64.0.10"}

      assert {:ok, updated} = VPN.update_connection(attrs)
      assert updated.status == :connected
      assert updated.vpn_ip == "100.64.0.10"
    end

    test "get_connection!/0 raises when connection not found" do
      :ets.delete_all_objects(:vpn_connection)

      assert_raise RuntimeError, "VPN connection not found", fn ->
        VPN.get_connection!()
      end
    end
  end

  describe "check_and_update_connectivity/0" do
    test "skips check when not connected" do
      VPN.update_connection(%{status: :disconnected})

      # Should not call Tailscale
      assert VPN.check_and_update_connectivity() == :ok
    end

    test "updates last_checked_at when connectivity is healthy" do
      VPN.update_connection(%{status: :connected})

      EdgeAdmin.TailscaleMock
      |> expect(:check_connectivity, fn -> {:ok, :healthy} end)

      assert :ok = VPN.check_and_update_connectivity()

      connection = VPN.get_connection!()
      assert connection.status == :connected

      assert_in_delta DateTime.to_unix(connection.last_checked_at),
                      DateTime.to_unix(DateTime.utc_now()),
                      2
    end

    test "updates VPN info when connectivity returns detailed info" do
      VPN.update_connection(%{status: :connected})

      vpn_info = %{vpn_ip: "100.64.0.15", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleMock
      |> expect(:check_connectivity, fn -> {:ok, vpn_info} end)

      assert :ok = VPN.check_and_update_connectivity()

      connection = VPN.get_connection!()
      assert connection.vpn_ip == "100.64.0.15"
      assert connection.vpn_hostname == "edge-admin"
    end

    test "marks as disconnected when connectivity fails" do
      connect_time = DateTime.add(DateTime.utc_now(), -300, :second)
      VPN.update_connection(%{status: :connected, connected_at: connect_time})

      EdgeAdmin.TailscaleMock
      |> expect(:check_connectivity, fn -> {:error, "Network unreachable"} end)

      assert :ok = VPN.check_and_update_connectivity()

      connection = VPN.get_connection!()
      assert connection.status == :disconnected
      assert connection.last_error == "Network unreachable"
      assert is_nil(connection.vpn_ip)
    end
  end

  describe "attempt_auto_reconnection/0" do
    test "skips when not disconnected" do
      VPN.update_connection(%{status: :connected})

      assert VPN.attempt_auto_reconnection() == :skipped
    end

    test "skips when manually disconnected" do
      VPN.update_connection(%{status: :disconnected, manual_disconnect: true})

      assert VPN.attempt_auto_reconnection() == :skipped
    end

    test "attempts reconnection when disconnected and not manual" do
      VPN.update_connection(%{status: :disconnected, manual_disconnect: false})

      EdgeAdmin.TailscaleMock
      |> expect(:connect_to_vpn, fn _url -> {:ok, :no_info} end)

      assert :ok = VPN.attempt_auto_reconnection()

      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert is_struct(connection.connected_at, DateTime)
    end

    test "handles reconnection failure" do
      VPN.update_connection(%{status: :disconnected, manual_disconnect: false})

      EdgeAdmin.TailscaleMock
      |> expect(:connect_to_vpn, fn _url -> {:error, "Auth failed"} end)

      assert :ok = VPN.attempt_auto_reconnection()

      connection = VPN.get_connection!()
      assert connection.status == :disconnected
      assert connection.last_error == "Auth failed"
    end

    test "updates with VPN info on successful reconnection" do
      VPN.update_connection(%{status: :disconnected, manual_disconnect: false})

      vpn_info = %{vpn_ip: "100.64.0.20", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleMock
      |> expect(:connect_to_vpn, fn _url -> {:ok, vpn_info} end)

      assert :ok = VPN.attempt_auto_reconnection()

      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert connection.vpn_ip == "100.64.0.20"
      assert connection.vpn_hostname == "edge-admin"
    end
  end

  describe "connect_to_vpn/0" do
    test "sets connecting status then handles success" do
      EdgeAdmin.TailscaleMock
      |> expect(:connect_to_vpn, fn _url -> {:ok, :no_info} end)

      assert :ok = VPN.connect_to_vpn()

      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert is_struct(connection.connected_at, DateTime)
      assert is_nil(connection.last_error)
    end

    test "handles connection failure" do
      EdgeAdmin.TailscaleMock
      |> expect(:connect_to_vpn, fn _url -> {:error, "Connection timeout"} end)

      assert :ok = VPN.connect_to_vpn()

      connection = VPN.get_connection!()
      assert connection.status == :disconnected
      assert connection.last_error == "Connection timeout"
    end
  end

  describe "disconnect_from_vpn/0" do
    test "successfully disconnects and sets manual_disconnect" do
      VPN.update_connection(%{status: :connected, vpn_ip: "100.64.0.10"})

      EdgeAdmin.TailscaleMock
      |> expect(:disconnect_from_vpn, fn -> :ok end)

      assert {:ok, _} = VPN.disconnect_from_vpn()

      connection = VPN.get_connection!()
      assert connection.status == :disconnected
      assert connection.manual_disconnect == true
      assert is_nil(connection.vpn_ip)
    end

    test "handles disconnect failure" do
      EdgeAdmin.TailscaleMock
      |> expect(:disconnect_from_vpn, fn -> {:error, "Failed to stop"} end)

      assert {:error, "Failed to stop"} = VPN.disconnect_from_vpn()
    end
  end
end
