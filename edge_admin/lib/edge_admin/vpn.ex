# edge_admin/lib/edge_admin/vpn.ex
defmodule EdgeAdmin.VPN do
  @moduledoc """
  VPN state management and business logic orchestration.

  This context handles connection state management and orchestrates
  VPN operations using the Tailscale module.
  """

  alias EdgeAdmin.VPN.ConnectionManager

  require Logger

  # Standard CRUD operations

  @doc """
  Gets the current VPN connection record.
  """
  def get_connection do
    ConnectionManager.get_connection()
  end

  @doc """
  Creates a new VPN connection record.
  Only used for initialization - there's always exactly one record.
  """
  def create_connection(attrs \\ %{}) do
    ConnectionManager.create_connection(attrs)
  end

  @doc """
  Updates the VPN connection record.
  """
  def update_connection(attrs) do
    ConnectionManager.update_connection(attrs)
  end

  @doc """
  Gets the connection, raising if not found.
  """
  def get_connection! do
    case get_connection() do
      {:ok, connection} -> connection
      {:error, _} -> raise "VPN connection not found"
    end
  end

  # Business logic functions for workers

  @doc """
  Checks connectivity and updates connection state accordingly.
  Called by the connectivity checker worker.
  """
  def check_and_update_connectivity do
    connection = get_connection!()

    if connection.status == :connected do
      Logger.debug("VPN: Monitoring connection")
      handle_connectivity_check(connection)
    else
      Logger.debug("VPN: Skipping connectivity check - not connected")
      :ok
    end
  end

  @doc """
  Attempts auto-reconnection if conditions are met.
  Called by the auto-reconnector worker.
  """
  def attempt_auto_reconnection do
    connection = get_connection!()

    if should_reconnect?(connection) do
      Logger.info("VPN: Attempting auto-reconnection")

      with {:ok, _} <- update_connection(%{status: :connecting}),
           {:ok, result} <-
             tailscale_module().connect_to_vpn(vpn_url(), enrollment_key(), "edge-admin") do
        handle_connection_success(result)
      else
        {:error, reason} -> handle_connection_failure(reason)
      end
    else
      Logger.debug("VPN: Skipping auto-reconnection - conditions not met")
      :skipped
    end
  end

  @doc """
  Manually connects to VPN.
  """
  def connect_to_vpn do
    Logger.info("VPN: Initiating manual connection")

    with {:ok, _} <- update_connection(%{status: :connecting}),
         {:ok, result} <-
           tailscale_module().connect_to_vpn(vpn_url(), enrollment_key(), "edge-admin") do
      handle_connection_success(result)
    else
      {:error, reason} -> handle_connection_failure(reason)
    end
  end

  @doc """
  Manually disconnects from VPN.
  """
  def disconnect_from_vpn do
    Logger.info("VPN: Initiating manual disconnection")

    case tailscale_module().disconnect_from_vpn() do
      :ok ->
        update_connection(%{
          status: :disconnected,
          vpn_ip: nil,
          vpn_hostname: nil,
          manual_disconnect: true,
          last_checked_at: DateTime.utc_now()
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions - result handlers

  defp handle_connectivity_check(current_connection) do
    case tailscale_module().check_connectivity() do
      {:ok, vpn_info} when is_map(vpn_info) ->
        update_connection_healthy(vpn_info)
        log_vpn_info_update(vpn_info)
        :ok

      {:ok, :healthy} ->
        update_connection_healthy()
        :ok

      {:error, reason} ->
        update_connection_lost(current_connection, reason)
    end
  end

  defp handle_connection_success(:no_info) do
    attrs = connection_success_attrs()
    update_and_log(attrs, "VPN: Connected successfully")
  end

  defp handle_connection_success(vpn_info) when is_map(vpn_info) do
    attrs = connection_success_attrs(vpn_info)

    update_and_log(
      attrs,
      "VPN: Connected successfully - IP: #{vpn_info[:vpn_ip]}, Hostname: #{vpn_info[:vpn_hostname]}"
    )
  end

  defp handle_connection_failure(reason) do
    attrs = %{
      status: :disconnected,
      last_error: reason,
      last_error_at: DateTime.utc_now()
    }

    update_and_log(attrs, "VPN: Connection failed - #{reason}")
  end

  # Helper functions

  defp connection_success_attrs(vpn_info \\ %{}) do
    base_attrs = %{
      status: :connected,
      connected_at: DateTime.utc_now(),
      last_error: nil,
      last_error_at: nil
    }

    Map.merge(base_attrs, vpn_info)
  end

  defp update_connection_healthy(vpn_info \\ %{}) do
    attrs =
      Map.merge(vpn_info, %{
        last_checked_at: DateTime.utc_now(),
        last_error: nil,
        last_error_at: nil
      })

    case update_connection(attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_connection_lost(current_connection, reason) do
    log_connection_duration(current_connection)

    attrs = %{
      status: :disconnected,
      vpn_ip: nil,
      vpn_hostname: nil,
      last_error: reason,
      last_error_at: DateTime.utc_now(),
      last_checked_at: DateTime.utc_now()
    }

    update_and_log(attrs, "VPN: Connection lost - #{reason}")
  end

  defp update_and_log(attrs, log_message) do
    case update_connection(attrs) do
      {:ok, _updated_connection} ->
        Logger.info(log_message)
        :ok

      {:error, reason} ->
        Logger.error("VPN: Failed to update connection status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp log_connection_duration(connection) do
    if connection.connected_at do
      duration_seconds = DateTime.diff(DateTime.utc_now(), connection.connected_at, :second)
      Logger.info("VPN: Connection was active for #{duration_seconds} seconds")
    end
  end

  defp log_vpn_info_update(vpn_info) do
    if vpn_info[:vpn_ip] || vpn_info[:vpn_hostname] do
      Logger.debug(
        "VPN: Connection details updated - IP: #{vpn_info[:vpn_ip]}, Hostname: #{vpn_info[:vpn_hostname]}"
      )
    end
  end

  defp should_reconnect?(connection) do
    connection.status == :disconnected && !connection.manual_disconnect
  end

  defp vpn_url do
    System.get_env("VPN_URL") || raise "VPN_URL environment variable not set"
  end

  defp tailscale_module do
    Application.get_env(:edge_admin, :tailscale_module, EdgeAdmin.Tailscale)
  end

  defp enrollment_key do
    System.get_env("ENROLLMENT_KEY") || raise "ENROLLMENT_KEY environment variable not set"
  end
end
