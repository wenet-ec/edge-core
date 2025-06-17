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

  describe "connection operations" do
    test "connect_to_vpn with various arities and response types" do
      vpn_info = %{vpn_ip: "100.64.0.10", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:ok, vpn_info}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "custom-hostname" ->
        {:ok, %{vpn_ip: "100.64.0.10", vpn_hostname: "custom-hostname"}}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "edge-admin" ->
        {:ok, :no_info}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "auth-key-123", "test-node" ->
        {:ok, %{vpn_ip: "100.64.0.15", vpn_hostname: "test-node"}}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "auth-key-123", "test-node" ->
        {:ok, :no_info}
      end)

      # Test 1-arity: default hostname
      assert {:ok, result} = Tailscale.connect_to_vpn("http://vpn.example.com")
      assert result == vpn_info

      # Test 2-arity: custom hostname with full info
      assert {:ok, result} = Tailscale.connect_to_vpn("http://vpn.example.com", "custom-hostname")
      assert result.vpn_hostname == "custom-hostname"

      # Test 2-arity: no info response
      assert {:ok, :no_info} = Tailscale.connect_to_vpn("http://vpn.example.com", "edge-admin")

      # Test 3-arity: enrollment key with full info
      assert {:ok, result} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "auth-key-123", "test-node")

      assert result.vpn_hostname == "test-node"

      # Test 3-arity: enrollment key with no info
      assert {:ok, :no_info} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "auth-key-123", "test-node")
    end

    test "connect_to_vpn error scenarios" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:error, "Connection timeout"}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "custom-hostname" ->
        {:error, "Connection timeout"}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "invalid-key", "test-node" ->
        {:error, "Invalid enrollment key"}
      end)

      # Test error cases for all arities
      assert {:error, "Connection timeout"} = Tailscale.connect_to_vpn("http://vpn.example.com")

      assert {:error, "Connection timeout"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "custom-hostname")

      assert {:error, "Invalid enrollment key"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "invalid-key", "test-node")
    end

    test "disconnect_from_vpn success and error cases" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:disconnect_from_vpn, fn -> :ok end)
      |> expect(:disconnect_from_vpn, fn -> {:error, "Failed to stop"} end)

      # Success case
      assert :ok = Tailscale.disconnect_from_vpn()

      # Error case
      assert {:error, "Failed to stop"} = Tailscale.disconnect_from_vpn()
    end
  end

  describe "status and monitoring operations" do
    test "check_connectivity with different response types" do
      vpn_info = %{vpn_ip: "100.64.0.15", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleClientMock
      |> expect(:check_connectivity, fn -> {:ok, :healthy} end)
      |> expect(:check_connectivity, fn -> {:ok, vpn_info} end)
      |> expect(:check_connectivity, fn -> {:error, "Network unreachable"} end)

      # Healthy status
      assert {:ok, :healthy} = Tailscale.check_connectivity()

      # VPN info available
      assert {:ok, result} = Tailscale.check_connectivity()
      assert result == vpn_info

      # Error case
      assert {:error, "Network unreachable"} = Tailscale.check_connectivity()
    end

    test "status_json success and error cases" do
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
      |> expect(:status_json, fn -> {:error, "JSON decode failed"} end)

      # Success case
      assert {:ok, result} = Tailscale.status_json()
      assert result == status_data

      # Error case
      assert {:error, "JSON decode failed"} = Tailscale.status_json()
    end

    test "connected? with different status data" do
      connected_status = %{
        "BackendState" => "Running",
        "Self" => %{"Online" => true}
      }

      disconnected_status = %{
        "BackendState" => "LoggedOut",
        "Self" => nil
      }

      invalid_data = "not a map"

      EdgeAdmin.TailscaleClientMock
      |> expect(:connected?, fn ^connected_status -> true end)
      |> expect(:connected?, fn ^disconnected_status -> false end)
      |> expect(:connected?, fn ^invalid_data -> false end)

      # Connected
      assert Tailscale.connected?(connected_status) == true

      # Disconnected
      assert Tailscale.connected?(disconnected_status) == false

      # Invalid data
      assert Tailscale.connected?(invalid_data) == false
    end

    test "get_vpn_ip with different scenarios" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:get_vpn_ip, fn -> {:ok, "100.64.0.20"} end)
      |> expect(:get_vpn_ip, fn -> {:error, :no_ip} end)
      |> expect(:get_vpn_ip, fn -> {:error, :status_failed} end)

      # IP available
      assert {:ok, "100.64.0.20"} = Tailscale.get_vpn_ip()

      # No IP available
      assert {:error, :no_ip} = Tailscale.get_vpn_ip()

      # Status check failed
      assert {:error, :status_failed} = Tailscale.get_vpn_ip()
    end
  end

  describe "utility operations" do
    test "start_daemon" do
      EdgeAdmin.TailscaleClientMock
      |> expect(:start_daemon, fn -> :ok end)

      assert :ok = Tailscale.start_daemon()
    end

    test "client configuration" do
      # Test default client availability
      Application.delete_env(:edge_admin, :tailscale_module)
      assert Code.ensure_loaded?(EdgeAdmin.Tailscale.Client)

      functions = EdgeAdmin.Tailscale.Client.__info__(:functions)
      assert Enum.member?(functions, {:connect_to_vpn, 1})
      assert Enum.member?(functions, {:connect_to_vpn, 2})
      assert Enum.member?(functions, {:connect_to_vpn, 3})

      # Restore mock
      Application.put_env(:edge_admin, :tailscale_module, EdgeAdmin.TailscaleClientMock)
      assert Application.get_env(:edge_admin, :tailscale_module) == EdgeAdmin.TailscaleClientMock
    end
  end

  describe "integration and edge cases" do
    test "complete connection workflows" do
      vpn_info = %{vpn_ip: "100.64.0.25", vpn_hostname: "edge-admin"}

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:ok, vpn_info}
      end)
      |> expect(:check_connectivity, fn -> {:ok, vpn_info} end)
      |> expect(:get_vpn_ip, fn -> {:ok, "100.64.0.25"} end)
      |> expect(:start_daemon, fn -> :ok end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "custom-host" ->
        {:ok, %{vpn_ip: "100.64.0.30", vpn_hostname: "custom-host"}}
      end)

      # Complete flow: connect -> check -> get IP
      assert {:ok, ^vpn_info} = Tailscale.connect_to_vpn("http://vpn.example.com")
      assert {:ok, ^vpn_info} = Tailscale.check_connectivity()
      assert {:ok, "100.64.0.25"} = Tailscale.get_vpn_ip()

      # Daemon start and connect flow
      assert :ok = Tailscale.start_daemon()
      assert {:ok, result} = Tailscale.connect_to_vpn("http://vpn.example.com", "custom-host")
      assert result.vpn_hostname == "custom-host"
    end

    test "retry and status monitoring scenarios" do
      initial_status = %{
        "BackendState" => "Running",
        "Self" => %{"Online" => true, "HostName" => "edge-admin"}
      }

      disconnected_status = %{
        "BackendState" => "LoggedOut",
        "Self" => nil
      }

      EdgeAdmin.TailscaleClientMock
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:error, "Temporary failure"}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com" ->
        {:ok, :no_info}
      end)
      |> expect(:status_json, fn -> {:ok, initial_status} end)
      |> expect(:connected?, fn ^initial_status -> true end)
      |> expect(:status_json, fn -> {:ok, disconnected_status} end)
      |> expect(:connected?, fn ^disconnected_status -> false end)

      # Connection retry scenario
      assert {:error, "Temporary failure"} = Tailscale.connect_to_vpn("http://vpn.example.com")
      assert {:ok, :no_info} = Tailscale.connect_to_vpn("http://vpn.example.com")

      # Status monitoring
      assert {:ok, ^initial_status} = Tailscale.status_json()
      assert Tailscale.connected?(initial_status) == true
      assert {:ok, ^disconnected_status} = Tailscale.status_json()
      assert Tailscale.connected?(disconnected_status) == false
    end

    test "edge cases and error conditions" do
      long_hostname = String.duplicate("a", 300)

      EdgeAdmin.TailscaleClientMock
      |> expect(:status_json, fn -> {:ok, %{}} end)
      |> expect(:connected?, fn %{} -> false end)
      |> expect(:get_vpn_ip, fn -> {:error, :no_ip} end)
      |> expect(:connect_to_vpn, fn "invalid-url" ->
        {:error, "Invalid URL format"}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", ^long_hostname ->
        {:error, "Hostname too long"}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "", "test-node" ->
        {:error, "Empty enrollment key"}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "instance-1" ->
        {:ok, %{vpn_hostname: "instance-1"}}
      end)
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "instance-2" ->
        {:ok, %{vpn_hostname: "instance-2"}}
      end)

      # Empty responses
      assert {:ok, %{}} = Tailscale.status_json()
      assert Tailscale.connected?(%{}) == false
      assert {:error, :no_ip} = Tailscale.get_vpn_ip()

      # Malformed inputs
      assert {:error, "Invalid URL format"} = Tailscale.connect_to_vpn("invalid-url")

      assert {:error, "Hostname too long"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", long_hostname)

      assert {:error, "Empty enrollment key"} =
               Tailscale.connect_to_vpn("http://vpn.example.com", "", "test-node")

      # Multiple instances
      assert {:ok, result1} = Tailscale.connect_to_vpn("http://vpn.example.com", "instance-1")
      assert result1.vpn_hostname == "instance-1"
      assert {:ok, result2} = Tailscale.connect_to_vpn("http://vpn.example.com", "instance-2")
      assert result2.vpn_hostname == "instance-2"
    end
  end
end
