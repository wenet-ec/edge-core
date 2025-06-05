# lib/edge_admin/vpn/workers/auto_reconnector.ex
defmodule EdgeAdmin.VPN.Workers.AutoReconnector do
  @moduledoc """
  Oban worker that attempts to reconnect to VPN when disconnected.

  This worker:
  - Only runs when status is :disconnected and manual_disconnect is false
  - Sets status to :connecting before attempting connection
  - Delegates actual connection logic to the configured VPN client
  - Updates connection state based on client response
  """

  use Oban.Worker, queue: :vpn, max_attempts: 3

  alias EdgeAdmin.VPN
  alias EdgeAdmin.VPN.Config, as: VPNConfig

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    current_connection = VPN.get_connection!()

    if should_attempt_reconnection?(current_connection) do
      Logger.info("AutoReconnector: Attempting VPN reconnection")
      attempt_reconnection()
    else
      Logger.debug("AutoReconnector: Skipping - preconditions not met (status: #{current_connection.status}, manual_disconnect: #{current_connection.manual_disconnect})")

      :ok
    end
  end

  defp should_attempt_reconnection?(connection) do
    connection.status == :disconnected && !connection.manual_disconnect
  end

  defp attempt_reconnection do
    # First, mark as connecting
    case VPN.update_connection(%{status: :connecting}) do
      {:ok, _} ->
        Logger.debug("AutoReconnector: Status set to :connecting")
        perform_connection_attempt()

      {:error, reason} ->
        Logger.error("AutoReconnector: Failed to update status to :connecting - #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp perform_connection_attempt do
    vpn_client = VPNConfig.client_module()

    case vpn_client.connect_to_vpn() do
      :ok ->
        # Successfully connected without additional info
        status_attrs = %{
          status: :connected,
          connected_at: DateTime.utc_now(),
          last_error: nil,
          last_error_at: nil
        }

        update_and_log(status_attrs, :success)

      {:ok, vpn_info} ->
        # Successfully connected with VPN info
        status_attrs =
          Map.merge(vpn_info, %{
            status: :connected,
            connected_at: DateTime.utc_now(),
            last_error: nil,
            last_error_at: nil
          })

        update_and_log(status_attrs, :success_with_info)

      {:error, error_message} ->
        # Connection failed
        status_attrs = %{
          status: :disconnected,
          last_error: error_message,
          last_error_at: DateTime.utc_now()
        }

        update_and_log(status_attrs, :failure)
    end
  end

  defp update_and_log(status_attrs, result_type) do
    case VPN.update_connection(status_attrs) do
      {:ok, updated_connection} ->
        log_reconnection_result(updated_connection, result_type)
        :ok

      {:error, reason} ->
        Logger.error("AutoReconnector: Failed to update connection status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp log_reconnection_result(connection, result_type) do
    case result_type do
      :success ->
        Logger.info("AutoReconnector: Successfully reconnected to VPN")

      :success_with_info ->
        Logger.info("AutoReconnector: Successfully reconnected - IP: #{connection.vpn_ip}, Hostname: #{connection.vpn_hostname}")

      :failure ->
        Logger.warning("AutoReconnector: Reconnection failed - #{connection.last_error}")
    end
  end
end
