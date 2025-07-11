# edge_admin/lib/edge_admin/tailscale.ex
defmodule EdgeAdmin.Tailscale do
  @moduledoc """
  The Tailscale context for VPN operations and node management.

  This context provides a unified interface for:
  - CLI operations (connect, disconnect, status) via Tailscale.Cli
  - API operations (enrollment keys, node info) via Tailscale.Api
  - Connection state management
  - VPN monitoring and auto-reconnection

  ## CLI Operations
  - `connect_to_vpn/3` - Connect using enrollment key
  - `disconnect_from_vpn/0` - Disconnect from VPN
  - `check_connectivity/0` - Check current connectivity status
  - `get_vpn_ip/0` - Get current VPN IP address

  ## API Operations
  - `create_enrollment_key/1` - Generate enrollment keys
  - `get_node_by_hostname/1` - Get node information
  - `list_nodes_for_user/1` - List nodes for a user

  ## Connection Management
  - `get_connection/0` - Get connection state
  - `update_connection/1` - Update connection state
  - `check_and_update_connectivity/0` - Monitor and update connectivity
  - `attempt_auto_reconnection/0` - Attempt auto-reconnection
  """

  alias EdgeAdmin.Tailscale.ConnectionManager

  require Logger

  @cli_client Application.compile_env(
                :edge_admin,
                :tailscale_cli_client,
                EdgeAdmin.Tailscale.Cli.Client
              )
  @api_client Application.compile_env(
                :edge_admin,
                :tailscale_api_client,
                EdgeAdmin.Tailscale.Api.Client
              )

  def connect_to_vpn(vpn_url, enrollment_key, hostname) do
    @cli_client.connect_to_vpn(vpn_url, enrollment_key, hostname)
  end

  def disconnect_from_vpn do
    @cli_client.disconnect_from_vpn()
  end

  def check_connectivity do
    @cli_client.check_connectivity()
  end

  def status_json do
    @cli_client.status_json()
  end

  def connected?(status_data) do
    @cli_client.connected?(status_data)
  end

  def start_daemon do
    @cli_client.start_daemon()
  end

  def get_vpn_ip do
    @cli_client.get_vpn_ip()
  end

  def get_node_by_hostname(vpn_hostname) do
    @api_client.get_node_by_hostname(vpn_hostname)
  end

  def list_nodes_for_user(user \\ "edge-nodes") do
    @api_client.list_nodes_for_user(user)
  end

  def create_enrollment_key(user \\ "edge-nodes") do
    @api_client.create_enrollment_key(user)
  end

  def get_user(username) do
    @api_client.get_user(username)
  end

  # Connection state management - delegate to ConnectionManager
  defdelegate get_connection(), to: ConnectionManager
  defdelegate create_connection(attrs \\ %{}), to: ConnectionManager
  defdelegate update_connection(attrs), to: ConnectionManager

  @doc """
  Gets the connection, raising if not found.
  """
  def get_connection! do
    case get_connection() do
      {:ok, connection} -> connection
      {:error, _} -> raise "Tailscale connection not found"
    end
  end

  # Business logic functions for workers

  def check_and_update_connectivity do
    connection = get_connection!()

    if connection.status == :connected do
      Logger.debug("Tailscale: Monitoring connection")
      handle_connectivity_check(connection)
    else
      Logger.debug("Tailscale: Skipping connectivity check - not connected")
      :ok
    end
  end

  def attempt_auto_reconnection do
    connection = get_connection!()

    if should_reconnect?(connection) do
      Logger.info("Tailscale: Attempting auto-reconnection")

      with {:ok, _} <- update_connection(%{status: :connecting}),
           {:ok, result} <- connect_to_vpn(vpn_url(), enrollment_key(), "edge-admin") do
        handle_connection_success(result)
      else
        {:error, reason} -> handle_connection_failure(reason)
      end
    else
      Logger.debug("Tailscale: Skipping auto-reconnection - conditions not met")
      :skipped
    end
  end

  def connect_to_vpn_manual do
    Logger.info("Tailscale: Initiating manual connection")

    with {:ok, _} <- update_connection(%{status: :connecting}),
         {:ok, result} <- connect_to_vpn(vpn_url(), enrollment_key(), "edge-admin") do
      handle_connection_success(result)
    else
      {:error, reason} -> handle_connection_failure(reason)
    end
  end

  def disconnect_from_vpn_manual do
    Logger.info("Tailscale: Initiating manual disconnection")

    case disconnect_from_vpn() do
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
    case check_connectivity() do
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
    update_and_log(attrs, "Tailscale: Connected successfully")
  end

  defp handle_connection_success(vpn_info) when is_map(vpn_info) do
    attrs = connection_success_attrs(vpn_info)

    update_and_log(
      attrs,
      "Tailscale: Connected successfully - IP: #{vpn_info[:vpn_ip]}, Hostname: #{vpn_info[:vpn_hostname]}"
    )
  end

  defp handle_connection_failure(reason) do
    attrs = %{
      status: :disconnected,
      last_error: reason,
      last_error_at: DateTime.utc_now()
    }

    update_and_log(attrs, "Tailscale: Connection failed - #{reason}")
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

    update_and_log(attrs, "Tailscale: Connection lost - #{reason}")
  end

  defp update_and_log(attrs, log_message) do
    case update_connection(attrs) do
      {:ok, _updated_connection} ->
        Logger.info(log_message)
        :ok

      {:error, reason} ->
        Logger.error("Tailscale: Failed to update connection status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp log_connection_duration(connection) do
    if connection.connected_at do
      duration_seconds = DateTime.diff(DateTime.utc_now(), connection.connected_at, :second)
      Logger.info("Tailscale: Connection was active for #{duration_seconds} seconds")
    end
  end

  defp log_vpn_info_update(vpn_info) do
    if vpn_info[:vpn_ip] || vpn_info[:vpn_hostname] do
      Logger.debug(
        "Tailscale: Connection details updated - IP: #{vpn_info[:vpn_ip]}, Hostname: #{vpn_info[:vpn_hostname]}"
      )
    end
  end

  defp should_reconnect?(connection) do
    connection.status == :disconnected && !connection.manual_disconnect
  end

  defp vpn_url do
    System.get_env("VPN_URL") || raise "VPN_URL environment variable not set"
  end

  defp enrollment_key do
    System.get_env("ENROLLMENT_KEY") || raise "ENROLLMENT_KEY environment variable not set"
  end
end
