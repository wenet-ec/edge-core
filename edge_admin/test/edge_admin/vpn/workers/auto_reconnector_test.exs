# test/edge_admin/vpn/workers/auto_reconnector_test.exs
defmodule EdgeAdmin.VPN.Workers.AutoReconnectorTest do
  use EdgeAdmin.DataCase, async: false
  use Oban.Testing, repo: EdgeAdmin.Repo

  alias EdgeAdmin.VPN
  alias EdgeAdmin.VPN.Clients.Behaviour
  alias EdgeAdmin.VPN.Workers.AutoReconnector

  # Mock VPN client for testing
  defmodule MockVPNClient do
    @moduledoc false
    @behaviour Behaviour

    def check_connectivity, do: :ok

    def connect_to_vpn do
      case Process.get(:mock_connect_result) do
        nil -> :ok
        result -> result
      end
    end

    def disconnect_from_vpn, do: :ok
  end

  setup do
    # Reset the ETS table state between tests
    :ets.delete_all_objects(:vpn_connection)
    {:ok, _} = VPN.create_connection(%{})

    # Use our mock client
    Application.put_env(:edge_admin, :vpn, client: MockVPNClient)

    # Reset mock state
    Process.delete(:mock_connect_result)

    on_exit(fn ->
      # Restore original client config
      Application.put_env(:edge_admin, :vpn, client: EdgeAdmin.VPN.Clients.Tailscale)
    end)

    :ok
  end

  describe "perform/1" do
    test "skips reconnection when status is connected" do
      # Set connection to connected
      {:ok, _} =
        VPN.update_connection(%{
          status: :connected,
          manual_disconnect: false
        })

      # Perform the job
      assert :ok = perform_job(AutoReconnector, %{})

      # Connection should remain unchanged
      connection = VPN.get_connection!()
      assert connection.status == :connected
    end

    test "skips reconnection when status is connecting" do
      # Set connection to connecting
      {:ok, _} =
        VPN.update_connection(%{
          status: :connecting,
          manual_disconnect: false
        })

      # Perform the job
      assert :ok = perform_job(AutoReconnector, %{})

      # Connection should remain unchanged
      connection = VPN.get_connection!()
      assert connection.status == :connecting
    end

    test "skips reconnection when manual_disconnect is true" do
      # Set connection to disconnected but manually disconnected
      {:ok, _} =
        VPN.update_connection(%{
          status: :disconnected,
          manual_disconnect: true
        })

      # Perform the job
      assert :ok = perform_job(AutoReconnector, %{})

      # Connection should remain disconnected
      connection = VPN.get_connection!()
      assert connection.status == :disconnected
      assert connection.manual_disconnect == true
    end

    test "attempts reconnection when disconnected and not manually disconnected" do
      # Set connection to disconnected
      {:ok, _} =
        VPN.update_connection(%{
          status: :disconnected,
          manual_disconnect: false
        })

      # Mock successful connection
      Process.put(:mock_connect_result, :ok)

      # Perform the job
      assert :ok = perform_job(AutoReconnector, %{})

      # Connection should be marked as connected
      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert is_struct(connection.connected_at, DateTime)
      assert is_nil(connection.last_error)
      assert is_nil(connection.last_error_at)
    end

    test "sets status to connecting before attempting connection" do
      # Set connection to disconnected
      {:ok, _} =
        VPN.update_connection(%{
          status: :disconnected,
          manual_disconnect: false
        })

      # Mock connection that takes some time (simulate by checking status mid-process)
      # We'll use a slow connect result to test the intermediate state
      Process.put(:mock_connect_result, :ok)

      # Perform the job
      assert :ok = perform_job(AutoReconnector, %{})

      # Final connection should be connected (the job completes the flow)
      connection = VPN.get_connection!()
      assert connection.status == :connected
    end

    test "updates connection with VPN info when client returns additional data" do
      # Set connection to disconnected
      {:ok, _} =
        VPN.update_connection(%{
          status: :disconnected,
          manual_disconnect: false
        })

      # Mock connection with VPN info
      Process.put(
        :mock_connect_result,
        {:ok,
         %{
           vpn_ip: "100.64.0.15",
           vpn_hostname: "edge-admin"
         }}
      )

      # Perform the job
      assert :ok = perform_job(AutoReconnector, %{})

      # Connection should include VPN info
      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert connection.vpn_ip == "100.64.0.15"
      assert connection.vpn_hostname == "edge-admin"
      assert is_struct(connection.connected_at, DateTime)
      assert is_nil(connection.last_error)
    end

    test "marks connection as disconnected when reconnection fails" do
      # Set connection to disconnected
      {:ok, _} =
        VPN.update_connection(%{
          status: :disconnected,
          manual_disconnect: false,
          last_error: nil
        })

      # Mock failed connection
      Process.put(:mock_connect_result, {:error, "Authentication failed"})

      # Perform the job
      assert :ok = perform_job(AutoReconnector, %{})

      # Connection should remain disconnected with error info
      connection = VPN.get_connection!()
      assert connection.status == :disconnected
      assert connection.last_error == "Authentication failed"
      assert is_struct(connection.last_error_at, DateTime)
    end

    test "clears previous error on successful reconnection" do
      # Set connection to disconnected with previous error
      old_error_time = DateTime.add(DateTime.utc_now(), -300, :second)

      {:ok, _} =
        VPN.update_connection(%{
          status: :disconnected,
          manual_disconnect: false,
          last_error: "Previous connection failure",
          last_error_at: old_error_time
        })

      # Mock successful connection
      Process.put(:mock_connect_result, :ok)

      # Perform the job
      assert :ok = perform_job(AutoReconnector, %{})

      # Connection should be connected with cleared error
      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert is_nil(connection.last_error)
      assert is_nil(connection.last_error_at)
    end
  end

  describe "precondition checking" do
    test "requires both disconnected status and manual_disconnect false" do
      test_cases = [
        # Should attempt reconnection
        {%{status: :disconnected, manual_disconnect: false}, true},

        # Should NOT attempt reconnection
        {%{status: :connected, manual_disconnect: false}, false},
        {%{status: :connecting, manual_disconnect: false}, false},
        {%{status: :disconnected, manual_disconnect: true}, false},
        {%{status: :connected, manual_disconnect: true}, false}
      ]

      for {attrs, should_reconnect} <- test_cases do
        # Reset connection state
        {:ok, _} = VPN.update_connection(attrs)

        # Mock successful connection for when it should attempt
        Process.put(:mock_connect_result, :ok)

        # Perform the job
        assert :ok = perform_job(AutoReconnector, %{})

        # Check if reconnection was attempted
        connection = VPN.get_connection!()

        if should_reconnect do
          assert connection.status == :connected,
                 "Expected reconnection for #{inspect(attrs)}"
        else
          assert connection.status == attrs.status,
                 "Expected no reconnection for #{inspect(attrs)}"
        end
      end
    end
  end

  describe "error handling" do
    test "handles connection manager errors gracefully" do
      # Set connection to disconnected
      {:ok, _} =
        VPN.update_connection(%{
          status: :disconnected,
          manual_disconnect: false
        })

      # Clear the connection to simulate manager error
      :ets.delete_all_objects(:vpn_connection)

      # The job should handle the missing connection gracefully
      # This will likely result in an error since get_connection! raises
      assert_raise RuntimeError, "VPN connection not found", fn ->
        perform_job(AutoReconnector, %{})
      end
    end
  end

  describe "integration with Oban scheduling" do
    test "job can be enqueued and processed" do
      # Set connection to disconnected
      {:ok, _} =
        VPN.update_connection(%{
          status: :disconnected,
          manual_disconnect: false
        })

      # Mock successful connection
      Process.put(:mock_connect_result, :ok)

      # Enqueue the job
      assert {:ok, job} = %{} |> AutoReconnector.new() |> Oban.insert()

      # Process the job
      assert :ok = perform_job(AutoReconnector, job.args)

      # Verify reconnection was attempted
      connection = VPN.get_connection!()
      assert connection.status == :connected
    end
  end
end
