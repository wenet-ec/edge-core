# edge_admin/test/edge_admin/vpn/connection_manager_test.exs
defmodule EdgeAdmin.VPN.ConnectionManagerTest do
  use ExUnit.Case, async: false

  alias EdgeAdmin.VPN.Connection
  alias EdgeAdmin.VPN.ConnectionManager

  setup do
    # Reset the ETS table state between tests instead of restarting the process
    :ets.delete_all_objects(:vpn_connection)

    # Initialize with a fresh connection
    {:ok, _} = ConnectionManager.create_connection(%{})
    :ok
  end

  describe "initialization" do
    test "creates initial connection record" do
      {:ok, connection} = ConnectionManager.get_connection()

      assert %Connection{} = connection
      assert connection.status == :disconnected
      assert connection.manual_disconnect == false
      assert is_struct(connection.last_checked_at, DateTime)
    end
  end

  describe "get_connection/0" do
    test "returns the singleton connection" do
      {:ok, connection} = ConnectionManager.get_connection()

      assert %Connection{} = connection
      assert connection.status == :disconnected
    end

    test "always returns the same connection instance" do
      {:ok, connection1} = ConnectionManager.get_connection()
      {:ok, connection2} = ConnectionManager.get_connection()

      assert connection1 == connection2
    end
  end

  describe "create_connection/1" do
    test "returns existing connection if already exists (singleton behavior)" do
      # Get the initial connection
      {:ok, initial_connection} = ConnectionManager.get_connection()

      # Try to create another one
      {:ok, created_connection} = ConnectionManager.create_connection(%{status: :connected})

      # Should return the existing one, not create a new one
      assert created_connection == initial_connection
      # Not :connected
      assert created_connection.status == :disconnected
    end

    test "creates connection with custom attributes if none exists" do
      # Clear existing connection
      :ets.delete_all_objects(:vpn_connection)

      custom_attrs = %{
        status: :connected,
        vpn_ip: "100.64.0.10",
        manual_disconnect: true
      }

      {:ok, connection} = ConnectionManager.create_connection(custom_attrs)

      assert connection.status == :connected
      assert connection.vpn_ip == "100.64.0.10"
      assert connection.manual_disconnect == true
    end
  end

  describe "update_connection/1" do
    test "updates existing connection with new attributes" do
      # Initial state
      {:ok, initial} = ConnectionManager.get_connection()
      assert initial.status == :disconnected
      assert initial.vpn_ip == nil

      # Update with new attributes
      update_attrs = %{
        status: :connected,
        vpn_ip: "100.64.0.10",
        vpn_hostname: "edge-admin",
        connected_at: DateTime.utc_now()
      }

      {:ok, updated} = ConnectionManager.update_connection(update_attrs)

      assert updated.status == :connected
      assert updated.vpn_ip == "100.64.0.10"
      assert updated.vpn_hostname == "edge-admin"
      assert is_struct(updated.connected_at, DateTime)

      # Verify the update persisted
      {:ok, retrieved} = ConnectionManager.get_connection()
      assert retrieved == updated
    end

    test "preserves existing fields when updating subset" do
      # Set initial state
      {:ok, _} =
        ConnectionManager.update_connection(%{
          status: :connected,
          vpn_ip: "100.64.0.10",
          vpn_hostname: "edge-admin"
        })

      # Update only status
      {:ok, updated} = ConnectionManager.update_connection(%{status: :disconnected})

      assert updated.status == :disconnected
      # Preserved
      assert updated.vpn_ip == "100.64.0.10"
      # Preserved
      assert updated.vpn_hostname == "edge-admin"
    end

    test "creates connection if none exists" do
      # Clear the ETS table to simulate no existing connection
      :ets.delete_all_objects(:vpn_connection)

      update_attrs = %{
        status: :connected,
        vpn_ip: "100.64.0.10"
      }

      {:ok, connection} = ConnectionManager.update_connection(update_attrs)

      assert connection.status == :connected
      assert connection.vpn_ip == "100.64.0.10"
    end

    test "handles concurrent updates safely" do
      # This tests the GenServer serialization
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            ConnectionManager.update_connection(%{vpn_ip: "100.64.0.#{i}"})
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn {:ok, _} -> true end)

      # Final state should be consistent
      {:ok, final_connection} = ConnectionManager.get_connection()
      assert String.starts_with?(final_connection.vpn_ip, "100.64.0.")
    end
  end

  describe "error handling" do
    test "handles invalid attributes gracefully" do
      # The GenServer call will exit because Connection.new/1 raises InvalidChangesetError
      # We should catch this as an :exit since it's happening in the GenServer process
      assert catch_exit(ConnectionManager.update_connection(%{status: :invalid_status}))
    end
  end
end
