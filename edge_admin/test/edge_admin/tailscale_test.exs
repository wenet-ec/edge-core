# edge_admin/test/edge_admin/tailscale_test.exs
defmodule EdgeAdmin.TailscaleTest do
  use EdgeAdmin.DataCase

  import Mox

  alias EdgeAdmin.Tailscale

  defmock(EdgeAdmin.TailscaleClientMock, for: EdgeAdmin.Tailscale.Behaviour)

  setup do
    # Configure the mock client for tests
    Application.put_env(:edge_admin, :tailscale_module, EdgeAdmin.TailscaleClientMock)

    on_exit(fn ->
      # Restore the original client
      Application.put_env(:edge_admin, :tailscale_module, EdgeAdmin.Tailscale.Client)
    end)

    :ok
  end

  describe "connect_to_vpn/3 - enrollment key connection" do
    test "successful connection with VPN info" do
      vpn_info = %{vpn_ip: "100.64.0.10", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "auth-key-123", "edge-admin" ->
        {:ok, vpn_info}
      end)

      assert {:ok, result} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "auth-key-123", "edge-admin")

      assert result == vpn_info
    end

    test "successful connection with no info" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "auth-key-123", "edge-admin" ->
        {:ok, :no_info}
      end)

      assert {:ok, :no_info} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "auth-key-123", "edge-admin")
    end

    test "connection failure" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "invalid-key", "edge-admin" ->
        {:error, "Invalid enrollment key"}
      end)

      assert {:error, "Invalid enrollment key"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "invalid-key", "edge-admin")
    end
  end

  describe "status and monitoring operations" do
    test "check_connectivity returns healthy" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:check_connectivity, fn -> {:ok, :healthy} end)

      assert {:ok, :healthy} = Tailscale.check_connectivity()
    end

    test "check_connectivity returns VPN info" do
      vpn_info = %{vpn_ip: "100.64.0.15", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleClientMock
      |> expect(:check_connectivity, fn -> {:ok, vpn_info} end)

      assert {:ok, result} = Tailscale.check_connectivity()
      assert result == vpn_info
    end

    test "check_connectivity returns error" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:check_connectivity, fn -> {:error, "Network unreachable"} end)

      assert {:error, "Network unreachable"} = Tailscale.check_connectivity()
    end

    test "get_vpn_ip success and failure" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:get_vpn_ip, fn -> {:ok, "100.64.0.20"} end)
      |> expect(:get_vpn_ip, fn -> {:error, :no_ip} end)

      # Success case
      assert {:ok, "100.64.0.20"} = Tailscale.get_vpn_ip()

      # Error case
      assert {:error, :no_ip} = Tailscale.get_vpn_ip()
    end
  end

  describe "utility operations" do
    test "disconnect_from_vpn success and error" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:disconnect_from_vpn, fn -> :ok end)
      |> expect(:disconnect_from_vpn, fn -> {:error, "Failed to stop"} end)

      assert :ok = Tailscale.disconnect_from_vpn()
      assert {:error, "Failed to stop"} = Tailscale.disconnect_from_vpn()
    end

    test "start_daemon" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:start_daemon, fn -> :ok end)

      assert :ok = Tailscale.start_daemon()
    end

    test "status_json and connected?" do
      connected_status = %{
        "BackendState" => "Running",
        "Self" => %{"Online" => true}
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:status_json, fn -> {:ok, connected_status} end)
      |> expect(:connected?, fn ^connected_status -> true end)

      assert {:ok, ^connected_status} = Tailscale.status_json()
      assert Tailscale.connected?(connected_status) == true
    end
  end

  describe "bootstrap integration scenario" do
    test "complete bootstrap connection flow" do
      # This simulates what happens in EdgeAdmin.Bootstrap
      vpn_info = %{vpn_ip: "100.64.0.25", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleClientMock
      |> expect(:start_daemon, fn -> :ok end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "enrollment-key", "edge-admin" ->
        {:ok, vpn_info}
      end)
      |> expect(:get_vpn_ip, fn -> {:ok, "100.64.0.25"} end)

      # Simulate bootstrap flow
      assert :ok = Tailscale.start_daemon()

      assert {:ok, ^vpn_info} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "enrollment-key", "edge-admin")

      assert {:ok, "100.64.0.25"} = Tailscale.get_vpn_ip()
    end
  end
end
