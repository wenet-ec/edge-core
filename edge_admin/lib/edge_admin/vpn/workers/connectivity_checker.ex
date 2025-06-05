# lib/edge_admin/vpn/workers/connectivity_checker.ex
defmodule EdgeAdmin.VPN.Workers.ConnectivityChecker do
  @moduledoc """
  Oban worker that monitors VPN connectivity when the connection status is :connected.

  This worker:
  - Only runs when the connection status is :connected
  - Delegates the actual connectivity check to the configured VPN client
  - Updates the connection state based on the check results
  - Logs connection changes and duration information
  """

  use Oban.Worker, queue: :vpn, max_attempts: 3

  alias EdgeAdmin.VPN
  alias EdgeAdmin.VPN.Config, as: VPNConfig

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    current_connection = VPN.get_connection!()

    if should_check_connectivity?(current_connection) do
      Logger.debug("ConnectivityChecker: Monitoring connection (status: #{current_connection.status})")

      perform_connectivity_check(current_connection)
    else
      Logger.debug("ConnectivityChecker: Skipping - only monitors :connected status (current: #{current_connection.status})")

      :ok
    end
  end

  # Only monitor when we believe we're connected
  defp should_check_connectivity?(connection) do
    connection.status == :connected
  end

  defp perform_connectivity_check(current_connection) do
    vpn_client = VPNConfig.client_module()

    case vpn_client.check_connectivity() do
      :ok ->
        # Still connected - update last_checked_at only
        status_attrs = %{
          status: :connected,
          last_checked_at: DateTime.utc_now(),
          last_error: nil,
          last_error_at: nil
        }

        update_and_log(current_connection, status_attrs, :still_connected)

      {:ok, vpn_info} ->
        # Still connected - update info and last_checked_at
        status_attrs =
          Map.merge(vpn_info, %{
            status: :connected,
            last_checked_at: DateTime.utc_now(),
            last_error: nil,
            last_error_at: nil
          })

        update_and_log(current_connection, status_attrs, :still_connected)

      {:error, error_message} ->
        # Connection lost - mark as disconnected
        status_attrs = %{
          status: :disconnected,
          last_checked_at: DateTime.utc_now(),
          vpn_ip: nil,
          vpn_hostname: nil,
          last_error: error_message,
          last_error_at: DateTime.utc_now()
        }

        update_and_log(current_connection, status_attrs, :connection_lost)
    end
  end

  defp update_and_log(current_connection, status_attrs, check_result) do
    case VPN.update_connection(status_attrs) do
      {:ok, updated_connection} ->
        log_check_result(current_connection, updated_connection, check_result)
        :ok

      {:error, reason} ->
        Logger.error("ConnectivityChecker: Failed to update connection status: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp log_check_result(current, updated, check_result) do
    case check_result do
      :still_connected ->
        # Only log if VPN details changed during the check
        if current.vpn_ip != updated.vpn_ip or current.vpn_hostname != updated.vpn_hostname do
          Logger.info("ConnectivityChecker: VPN details updated - IP: #{updated.vpn_ip}, Hostname: #{updated.vpn_hostname}")
        end

      :connection_lost ->
        Logger.warning("ConnectivityChecker: Connection lost - #{updated.last_error}")

        # Log connection duration if we know when it was established
        if current.connected_at do
          duration_seconds = DateTime.diff(DateTime.utc_now(), current.connected_at, :second)

          Logger.info("ConnectivityChecker: Connection was active for #{duration_seconds} seconds")
        end
    end
  end
end
