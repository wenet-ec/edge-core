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

  describe "connect_to_vpn/1" do
    test "connects successfully with default hostname" do
      expected_result = %{
        vpn_ip: "100.64.0.10",
        vpn_hostname: "edge-admin"
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:ok, expected_result}
      end)

      assert {:ok, result} = Tailscale.connect_to_vpn("http://vpn.example.com")
      assert result == expected_result
    end

    test "returns error when connection fails" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:error, "Connection timeout"}
      end)

      assert {:error, "Connection timeout"} = Tailscale.connect_to_vpn("http://vpn.example.com")
    end
  end

  describe "connect_to_vpn/2" do
    test "connects successfully with custom hostname" do
      expected_result = %{
        vpn_ip: "100.64.0.10",
        vpn_hostname: "custom-hostname"
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "custom-hostname" ->
        {:ok, expected_result}
      end)

      assert {:ok, result} = Tailscale.connect_to_vpn("http://vpn.example.com", "custom-hostname")
      assert result == expected_result
    end

    test "returns no_info when connection succeeds but no details available" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "edge-admin" ->
        {:ok, :no_info}
      end)

      assert {:ok, :no_info} = Tailscale.connect_to_vpn("http://vpn.example.com", "edge-admin")
    end

    test "returns error when connection fails" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "custom-hostname" ->
        {:error, "Connection timeout"}
      end)

      assert {:error, "Connection timeout"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "custom-hostname")
    end
  end

  describe "connect_to_vpn/3" do
    test "connects successfully with enrollment key" do
      expected_result = %{
        vpn_ip: "100.64.0.15",
        vpn_hostname: "test-node"
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "auth-key-123", "test-node" ->
        {:ok, expected_result}
      end)

      assert {:ok, result} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "auth-key-123", "test-node")

      assert result == expected_result
    end

    test "returns no_info when connection succeeds but no details available" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "auth-key-123", "test-node" ->
        {:ok, :no_info}
      end)

      assert {:ok, :no_info} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "auth-key-123", "test-node")
    end

    test "returns error when enrollment key connection fails" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "invalid-key", "test-node" ->
        {:error, "Invalid enrollment key"}
      end)

      assert {:error, "Invalid enrollment key"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "invalid-key", "test-node")
    end
  end

  describe "check_connectivity/0" do
    test "returns healthy status when connected" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:check_connectivity, fn -> {:ok, :healthy} end)

      assert {:ok, :healthy} = Tailscale.check_connectivity()
    end

    test "returns VPN info when available" do
      vpn_info = %{vpn_ip: "100.64.0.15", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleClientMock
      |> expect(:check_connectivity, fn -> {:ok, vpn_info} end)

      assert {:ok, result} = Tailscale.check_connectivity()
      assert result == vpn_info
    end

    test "returns error when connectivity check fails" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:check_connectivity, fn -> {:error, "Network unreachable"} end)

      assert {:error, "Network unreachable"} = Tailscale.check_connectivity()
    end
  end

  describe "disconnect_from_vpn/0" do
    test "disconnects successfully" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:disconnect_from_vpn, fn -> :ok end)

      assert :ok = Tailscale.disconnect_from_vpn()
    end

    test "returns error when disconnect fails" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:disconnect_from_vpn, fn -> {:error, "Failed to stop"} end)

      assert {:error, "Failed to stop"} = Tailscale.disconnect_from_vpn()
    end
  end

  describe "status_json/0" do
    test "returns status data successfully" do
      status_data = %{
        "BackendState" => "Running",
        "Self" => %{
          "Online" => true,
          "TailscaleIPs" => ["100.64.0.10"],
          "HostName" => "edge-admin"
        }
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:status_json, fn -> {:ok, status_data} end)

      assert {:ok, result} = Tailscale.status_json()
      assert result == status_data
    end

    test "returns error when status check fails" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:status_json, fn -> {:error, "JSON decode failed"} end)

      assert {:error, "JSON decode failed"} = Tailscale.status_json()
    end
  end

  describe "connected?/1" do
    test "returns true for connected status" do
      status_data = %{
        "BackendState" => "Running",
        "Self" => %{"Online" => true}
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:connected?, fn ^status_data -> true end)

      assert Tailscale.connected?(status_data) == true
    end

    test "returns false for disconnected status" do
      status_data = %{
        "BackendState" => "LoggedOut",
        "Self" => nil
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:connected?, fn ^status_data -> false end)

      assert Tailscale.connected?(status_data) == false
    end

    test "returns false for invalid status data" do
      invalid_data = "not a map"

      EdgeAdmin.TailscaleClientMock
      |> expect(:connected?, fn ^invalid_data -> false end)

      assert Tailscale.connected?(invalid_data) == false
    end
  end

  describe "start_daemon/0" do
    test "starts daemon successfully" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:start_daemon, fn -> :ok end)

      assert :ok = Tailscale.start_daemon()
    end
  end

  describe "get_vpn_ip/0" do
    test "returns VPN IP when available" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:get_vpn_ip, fn -> {:ok, "100.64.0.20"} end)

      assert {:ok, "100.64.0.20"} = Tailscale.get_vpn_ip()
    end

    test "returns error when no IP available" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:get_vpn_ip, fn -> {:error, :no_ip} end)

      assert {:error, :no_ip} = Tailscale.get_vpn_ip()
    end

    test "returns error when status check fails" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:get_vpn_ip, fn -> {:error, :status_failed} end)

      assert {:error, :status_failed} = Tailscale.get_vpn_ip()
    end
  end

  describe "configuration" do
    test "uses default client when no configuration provided" do
      # Temporarily remove the mock to test default behavior
      Application.delete_env(:edge_admin, :tailscale_module)

      # Check if the module exists and is compiled
      assert Code.ensure_loaded?(EdgeAdmin.Tailscale.Client)

      # This would normally call the real client, but we'll just verify the config lookup
      # works by checking the private client/0 function behavior indirectly
      functions = EdgeAdmin.Tailscale.Client.__info__(:functions)

      # Check that the expected functions exist
      assert Enum.member?(functions, {:connect_to_vpn, 1})
      assert Enum.member?(functions, {:connect_to_vpn, 2})
      assert Enum.member?(functions, {:connect_to_vpn, 3})

      # Restore mock for other tests
      Application.put_env(:edge_admin, :tailscale_module, EdgeAdmin.TailscaleClientMock)
    end

    test "uses configured client module" do
      # Test that our mock is properly configured
      assert Application.get_env(:edge_admin, :tailscale_module) == EdgeAdmin.TailscaleClientMock
    end
  end

  describe "integration scenarios" do
    test "complete connection flow with status checks" do
      # Simulate a complete flow: connect -> check status -> get IP
      vpn_info = %{vpn_ip: "100.64.0.25", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:ok, vpn_info}
      end)
      |> expect(:check_connectivity, fn -> {:ok, vpn_info} end)
      |> expect(:get_vpn_ip, fn -> {:ok, "100.64.0.25"} end)

      # Connect (using 1-parameter version)
      assert {:ok, ^vpn_info} = Tailscale.connect_to_vpn("http://vpn.example.com")

      # Check connectivity
      assert {:ok, ^vpn_info} = Tailscale.check_connectivity()

      # Get IP
      assert {:ok, "100.64.0.25"} = Tailscale.get_vpn_ip()
    end

    test "connection retry scenario" do
      # First connection fails, second succeeds
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:error, "Temporary failure"}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:ok, :no_info}
      end)

      # First attempt fails
      assert {:error, "Temporary failure"} = Tailscale.connect_to_vpn("http://vpn.example.com")

      # Second attempt succeeds
      assert {:ok, :no_info} = Tailscale.connect_to_vpn("http://vpn.example.com")
    end

    test "daemon start and connect flow" do
      # Simulate starting daemon then connecting
      EdgeAdmin.TailscaleClientMock
      |> expect(:start_daemon, fn -> :ok end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "custom-host" ->
        {:ok, %{vpn_ip: "100.64.0.30", vpn_hostname: "custom-host"}}
      end)

      assert :ok = Tailscale.start_daemon()

      assert {:ok, result} = Tailscale.connect_to_vpn("http://vpn.example.com", "custom-host")
      assert result.vpn_ip == "100.64.0.30"
      assert result.vpn_hostname == "custom-host"
    end

    test "status monitoring scenario" do
      # Simulate checking status, then status changes
      initial_status = %{
        "BackendState" => "Running",
        "Self" => %{"Online" => true, "HostName" => "edge-admin"}
      }

      disconnected_status = %{
        "BackendState" => "LoggedOut",
        "Self" => nil
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:status_json, fn -> {:ok, initial_status} end)
      |> expect(:connected?, fn ^initial_status -> true end)
      |> expect(:status_json, fn -> {:ok, disconnected_status} end)
      |> expect(:connected?, fn ^disconnected_status -> false end)

      # Initially connected
      assert {:ok, ^initial_status} = Tailscale.status_json()
      assert Tailscale.connected?(initial_status) == true

      # Later disconnected
      assert {:ok, ^disconnected_status} = Tailscale.status_json()
      assert Tailscale.connected?(disconnected_status) == false
    end
  end

  describe "edge cases" do
    test "handles nil and empty responses gracefully" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:status_json, fn -> {:ok, %{}} end)
      |> expect(:connected?, fn %{} -> false end)
      |> expect(:get_vpn_ip, fn -> {:error, :no_ip} end)

      assert {:ok, %{}} = Tailscale.status_json()
      assert Tailscale.connected?(%{}) == false
      assert {:error, :no_ip} = Tailscale.get_vpn_ip()
    end

    test "handles malformed VPN URLs" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "invalid-url" ->
        {:error, "Invalid URL format"}
      end)

      assert {:error, "Invalid URL format"} = Tailscale.connect_to_vpn("invalid-url")
    end

    test "handles extremely long hostnames" do
      long_hostname = String.duplicate("a", 300)

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", ^long_hostname ->
        {:error, "Hostname too long"}
      end)

      assert {:error, "Hostname too long"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", long_hostname)
    end

    test "handles empty enrollment keys" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "", "test-node" ->
        {:error, "Empty enrollment key"}
      end)

      assert {:error, "Empty enrollment key"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "", "test-node")
    end
  end

  describe "multiple client instances" do
    test "supports different hostnames for different instances" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "instance-1" ->
        {:ok, %{vpn_hostname: "instance-1"}}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "instance-2" ->
        {:ok, %{vpn_hostname: "instance-2"}}
      end)

      assert {:ok, result1} = Tailscale.connect_to_vpn("http://vpn.example.com", "instance-1")
      assert result1.vpn_hostname == "instance-1"

      assert {:ok, result2} = Tailscale.connect_to_vpn("http://vpn.example.com", "instance-2")
      assert result2.vpn_hostname == "instance-2"
    end
  end
end
