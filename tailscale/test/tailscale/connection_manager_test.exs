# tailscale/test/tailscale/connection_manager_test.exs
defmodule Tailscale.ConnectionManagerTest do
  use ExUnit.Case
  import Tailscale.Factory

  alias Tailscale.{Connection, ConnectionManager}

  setup do
    # Start a fresh ConnectionManager for each test
    {:ok, pid} = start_supervised(ConnectionManager)
    ConnectionManager.reset_connection()
    %{manager_pid: pid}
  end

  describe "get_connection/0" do
    test "returns default connection when none exists" do
      {:ok, connection} = ConnectionManager.get_connection()
      
      assert %Connection{} = connection
      assert connection.status == :disconnected
      assert connection.manual_disconnect == false
    end
  end

  describe "create_connection/1" do
    test "creates connection with default attributes" do
      {:ok, connection} = ConnectionManager.create_connection()
      
      assert %Connection{} = connection
      assert connection.status == :disconnected
    end

    test "creates connection with custom attributes" do
      attrs = %{
        status: :connected,
        vpn_ip: "100.64.0.1",
        vpn_hostname: "test-node"
      }
      
      {:ok, connection} = ConnectionManager.create_connection(attrs)
      
      assert connection.status == :connected
      assert connection.vpn_ip == "100.64.0.1"
      assert connection.vpn_hostname == "test-node"
    end

    test "returns error for invalid attributes" do
      attrs = %{status: :invalid_status}
      
      {:error, reason} = ConnectionManager.create_connection(attrs)
      
      assert String.contains?(reason, "Invalid status:")
    end
  end

  describe "update_connection/2" do
    test "updates existing connection" do
      {:ok, original_connection} = ConnectionManager.get_connection()
      
      attrs = %{
        status: :connected,
        vpn_ip: "100.64.0.1"
      }
      
      {:ok, updated_connection} = ConnectionManager.update_connection(original_connection, attrs)
      
      assert updated_connection.status == :connected
      assert updated_connection.vpn_ip == "100.64.0.1"
      assert updated_connection.updated_at != original_connection.updated_at
    end

    test "creates connection if none exists during update" do
      ConnectionManager.reset_connection()
      # Remove the default connection that gets created
      {:ok, _} = GenServer.call(ConnectionManager, {:update_connection, nil, %{status: :connecting}})
      
      attrs = %{
        status: :connected,
        vpn_ip: "100.64.0.1"
      }
      
      {:ok, connection} = ConnectionManager.update_connection(nil, attrs)
      
      assert connection.status == :connected
      assert connection.vpn_ip == "100.64.0.1"
    end

    test "returns error for invalid update attributes" do
      {:ok, connection} = ConnectionManager.get_connection()
      
      {:error, reason} = ConnectionManager.update_connection(connection, %{status: :invalid})
      
      assert String.contains?(reason, "Invalid status:")
    end
  end

  describe "reset_connection/0" do
    test "resets connection to default state" do
      # First, create a connected connection
      ConnectionManager.create_connection(%{
        status: :connected,
        vpn_ip: "100.64.0.1"
      })
      
      {:ok, reset_connection} = ConnectionManager.reset_connection()
      
      assert reset_connection.status == :disconnected
      assert reset_connection.vpn_ip == nil
    end
  end

  describe "GenServer state management" do
    test "maintains state across calls" do
      # Create a connection
      {:ok, connection1} = ConnectionManager.create_connection(%{status: :connecting})
      
      # Get the connection - should be the same
      {:ok, connection2} = ConnectionManager.get_connection()
      
      assert connection1.status == connection2.status
      assert connection1.inserted_at == connection2.inserted_at
    end

    test "handles concurrent updates" do
      {:ok, original} = ConnectionManager.get_connection()
      
      # Simulate concurrent updates
      tasks = 1..5
      |> Enum.map(fn i ->
        Task.async(fn ->
          ConnectionManager.update_connection(original, %{vpn_hostname: "node-#{i}"})
        end)
      end)
      
      results = Enum.map(tasks, &Task.await/1)
      
      # All should succeed
      assert Enum.all?(results, fn {result, _} -> result == :ok end)
      
      # Final state should be consistent
      {:ok, final_connection} = ConnectionManager.get_connection()
      assert final_connection.vpn_hostname != nil
    end
  end
end