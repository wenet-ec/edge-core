# tailscale/test/tailscale_test.exs
defmodule TailscaleTest do
  use ExUnit.Case
  import Mox
  import Tailscale.Factory

  alias Tailscale.Cli.MockClient, as: MockCliClient
  alias Tailscale.Api.MockClient, as: MockApiClient

  setup :verify_on_exit!

  describe "connection management" do
    test "get_connection returns a default connection" do
      {:ok, connection} = Tailscale.get_connection()
      assert connection.status == :disconnected
      assert connection.manual_disconnect == false
    end

    test "update_connection updates connection state" do
      {:ok, connection} = Tailscale.get_connection()
      
      {:ok, updated_connection} = Tailscale.update_connection(connection, %{
        status: :connected,
        vpn_ip: "100.64.0.1"
      })
      
      assert updated_connection.status == :connected
      assert updated_connection.vpn_ip == "100.64.0.1"
    end
  end

  describe "CLI operations" do
    test "connect_to_vpn delegates to CLI client" do
      MockCliClient
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "key123", "test-node" ->
        {:ok, %{vpn_ip: "100.64.0.1", vpn_hostname: "test-node"}}
      end)

      result = Tailscale.connect_to_vpn("http://vpn.example.com", "key123", "test-node")
      assert {:ok, %{vpn_ip: "100.64.0.1", vpn_hostname: "test-node"}} = result
    end

    test "check_connectivity delegates to CLI client" do
      MockCliClient
      |> expect(:check_connectivity, fn -> {:ok, :healthy} end)

      result = Tailscale.check_connectivity()
      assert {:ok, :healthy} = result
    end

    test "status_json delegates to CLI client" do
      status_data = build(:tailscale_status)
      
      MockCliClient
      |> expect(:status_json, fn -> {:ok, status_data} end)

      result = Tailscale.status_json()
      assert {:ok, ^status_data} = result
    end
  end

  describe "API operations" do
    test "get_node_by_hostname delegates to API client" do
      node_data = build(:vpn_node)
      
      MockApiClient
      |> expect(:get_node_by_hostname, fn "test-node" -> {:ok, node_data} end)

      result = Tailscale.get_node_by_hostname("test-node")
      assert {:ok, ^node_data} = result
    end

    test "create_enrollment_key delegates to API client" do
      key_data = build(:enrollment_key)
      
      MockApiClient
      |> expect(:create_enrollment_key, fn "edge-nodes" -> {:ok, key_data} end)

      result = Tailscale.create_enrollment_key("edge-nodes")
      assert {:ok, ^key_data} = result
    end
  end

  describe "business logic" do
    test "check_and_update_connectivity skips when disconnected" do
      # Default connection is disconnected
      result = Tailscale.check_and_update_connectivity()
      assert :ok = result
    end

    test "attempt_auto_reconnection with hostname provider function" do
      hostname_fn = fn -> "generated-hostname" end
      
      MockCliClient
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "key123", "generated-hostname" ->
        {:ok, %{vpn_ip: "100.64.0.1", vpn_hostname: "generated-hostname"}}
      end)

      result = Tailscale.attempt_auto_reconnection("http://vpn.example.com", "key123", hostname_fn)
      assert :ok = result
    end

    test "connect_to_vpn_manual with hostname provider tuple" do
      hostname_provider = {String, :upcase, ["test-node"]}
      
      MockCliClient
      |> expect(:connect_to_vpn, fn "http://vpn.example.com", "key123", "TEST-NODE" ->
        {:ok, %{vpn_ip: "100.64.0.1", vpn_hostname: "TEST-NODE"}}
      end)

      result = Tailscale.connect_to_vpn_manual("http://vpn.example.com", "key123", hostname_provider)
      assert :ok = result
    end
  end
end
