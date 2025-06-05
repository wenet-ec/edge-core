# test/edge_admin/vpn/workers/connectivity_checker_test.exs
defmodule EdgeAdmin.VPN.Workers.ConnectivityCheckerTest do
  use EdgeAdmin.DataCase, async: false
  use Oban.Testing, repo: EdgeAdmin.Repo

  alias EdgeAdmin.VPN
  alias EdgeAdmin.VPN.Clients.Behaviour
  alias EdgeAdmin.VPN.Workers.ConnectivityChecker

  # Mock VPN client for testing
  defmodule MockVPNClient do
    @moduledoc false
    @behaviour Behaviour

    def check_connectivity do
      case Process.get(:mock_connectivity_result) do
        nil -> :ok
        result -> result
      end
    end

    def connect_to_vpn, do: :ok
    def disconnect_from_vpn, do: :ok
  end

  setup do
    # Reset the ETS table state between tests
    :ets.delete_all_objects(:vpn_connection)
    {:ok, _} = VPN.create_connection(%{})

    # Use our mock client
    Application.put_env(:edge_admin, :vpn, client: MockVPNClient)

    # Reset mock state
    Process.delete(:mock_connectivity_result)

    on_exit(fn ->
      # Restore original client config
      Application.put_env(:edge_admin, :vpn, client: EdgeAdmin.VPN.Clients.Tailscale)
    end)

    :ok
  end

  describe "perform/1" do
    test "skips check when connection status is not connected" do
      # Set connection to disconnected
      {:ok, _} = VPN.update_connection(%{status: :disconnected})

      # Perform the job
      assert :ok = perform_job(ConnectivityChecker, %{})

      # Connection should remain unchanged
      connection = VPN.get_connection!()
      assert connection.status == :disconnected
    end

    test "skips check when connection status is connecting" do
      # Set connection to connecting
      {:ok, _} = VPN.update_connection(%{status: :connecting})

      # Perform the job
      assert :ok = perform_job(ConnectivityChecker, %{})

      # Connection should remain unchanged
      connection = VPN.get_connection!()
      assert connection.status == :connecting
    end

    test "updates last_checked_at when connection is still healthy" do
      # Set connection to connected
      old_time = DateTime.add(DateTime.utc_now(), -60, :second)

      {:ok, _} =
        VPN.update_connection(%{
          status: :connected,
          last_checked_at: old_time
        })

      # Mock successful connectivity check
      Process.put(:mock_connectivity_result, :ok)

      # Perform the job
      assert :ok = perform_job(ConnectivityChecker, %{})

      # Connection should remain connected with updated timestamp
      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert DateTime.after?(connection.last_checked_at, old_time)
      assert is_nil(connection.last_error)
    end

    test "updates VPN info when connectivity check returns additional data" do
      # Set connection to connected
      {:ok, _} =
        VPN.update_connection(%{
          status: :connected,
          vpn_ip: nil,
          vpn_hostname: nil
        })

      # Mock connectivity check with VPN info
      Process.put(
        :mock_connectivity_result,
        {:ok,
         %{
           vpn_ip: "100.64.0.10",
           vpn_hostname: "edge-admin"
         }}
      )

      # Perform the job
      assert :ok = perform_job(ConnectivityChecker, %{})

      # Connection should be updated with VPN info
      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert connection.vpn_ip == "100.64.0.10"
      assert connection.vpn_hostname == "edge-admin"
      assert is_nil(connection.last_error)
    end

    test "marks connection as disconnected when connectivity check fails" do
      # Set connection to connected with VPN details
      connect_time = DateTime.add(DateTime.utc_now(), -300, :second)

      {:ok, _} =
        VPN.update_connection(%{
          status: :connected,
          vpn_ip: "100.64.0.10",
          vpn_hostname: "edge-admin",
          connected_at: connect_time
        })

      # Mock failed connectivity check
      Process.put(:mock_connectivity_result, {:error, "Network unreachable"})

      # Perform the job
      assert :ok = perform_job(ConnectivityChecker, %{})

      # Connection should be marked as disconnected
      connection = VPN.get_connection!()
      assert connection.status == :disconnected
      assert is_nil(connection.vpn_ip)
      assert is_nil(connection.vpn_hostname)
      assert connection.last_error == "Network unreachable"
      assert is_struct(connection.last_error_at, DateTime)
    end

    test "clears error information when connectivity succeeds after previous failure" do
      # Set connection to connected with previous error
      old_error_time = DateTime.add(DateTime.utc_now(), -600, :second)

      {:ok, _} =
        VPN.update_connection(%{
          status: :connected,
          last_error: "Previous connection issue",
          last_error_at: old_error_time
        })

      # Mock successful connectivity check
      Process.put(:mock_connectivity_result, :ok)

      # Perform the job
      assert :ok = perform_job(ConnectivityChecker, %{})

      # Connection should clear error info on successful check
      connection = VPN.get_connection!()
      assert connection.status == :connected
      assert is_nil(connection.last_error)
      assert is_nil(connection.last_error_at)
    end
  end

  describe "error handling" do
    test "handles connection manager errors gracefully" do
      # Set connection to connected
      {:ok, _} = VPN.update_connection(%{status: :connected})

      # Mock successful connectivity
      Process.put(:mock_connectivity_result, :ok)

      # Clear the connection to simulate manager error
      :ets.delete_all_objects(:vpn_connection)

      # The job should handle the missing connection gracefully
      # This will likely result in an error since get_connection! raises
      assert_raise RuntimeError, "VPN connection not found", fn ->
        perform_job(ConnectivityChecker, %{})
      end
    end
  end

  describe "integration with Oban scheduling" do
    test "job can be enqueued and processed" do
      # Set connection to connected
      {:ok, _} = VPN.update_connection(%{status: :connected})

      # Mock successful connectivity
      Process.put(:mock_connectivity_result, :ok)

      # Enqueue the job
      assert {:ok, job} = %{} |> ConnectivityChecker.new() |> Oban.insert()

      # Process the job
      assert :ok = perform_job(ConnectivityChecker, job.args)

      # Verify the connection was checked
      connection = VPN.get_connection!()
      assert connection.status == :connected
    end
  end
end
