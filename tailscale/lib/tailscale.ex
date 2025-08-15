# tailscale/lib/tailscale.ex
defmodule Tailscale do
  @moduledoc """
  A shared Tailscale library for VPN operations and node management.

  This library provides a unified interface for:
  - CLI operations (connect, disconnect, status) via configurable clients
  - API operations (enrollment keys, node info) via configurable clients
  - Connection state management
  - VPN monitoring and auto-reconnection workers

  ## Configuration

  The library uses application configuration for customization:

      config :tailscale,
        cli_client: MyApp.TailscaleCliClient,
        api_client: MyApp.TailscaleApiClient,
        hostname_provider: MyApp.HostnameProvider

  ## Usage

      # Connect to VPN
      Tailscale.connect_to_vpn(vpn_url, enrollment_key, hostname)

      # Check connectivity
      Tailscale.check_connectivity()

      # Manage connection state
      {:ok, connection} = Tailscale.get_connection()
      Tailscale.update_connection(connection, %{status: :connected})
  """

  alias Tailscale.ConnectionManager

  require Logger

  # CLI Operations
  def connect_to_vpn(vpn_url, enrollment_key, hostname) do
    cli_client().connect_to_vpn(vpn_url, enrollment_key, hostname)
  end

  def disconnect_from_vpn do
    cli_client().disconnect_from_vpn()
  end

  def check_connectivity do
    cli_client().check_connectivity()
  end

  def status_json do
    cli_client().status_json()
  end

  def connected?(status_data) do
    cli_client().connected?(status_data)
  end

  def start_daemon do
    cli_client().start_daemon()
  end

  def get_vpn_ip do
    cli_client().get_vpn_ip()
  end

  # API Operations
  def get_node_by_hostname(vpn_hostname) do
    api_client().get_node_by_hostname(vpn_hostname)
  end

  def list_nodes_for_user(user \\ "edge-nodes") do
    api_client().list_nodes_for_user(user)
  end

  def create_enrollment_key(user \\ "edge-nodes") do
    api_client().create_enrollment_key(user)
  end

  def get_user(username) do
    api_client().get_user(username)
  end

  # Connection State Management
  def get_connection do
    ConnectionManager.get_connection()
  end

  def create_connection(attrs \\ %{}) do
    ConnectionManager.create_connection(attrs)
  end

  def update_connection(connection, attrs) do
    ConnectionManager.update_connection(connection, attrs)
  end

  @doc """
  Gets the connection, raising if not found.
  """
  def get_connection! do
    case get_connection() do
      {:ok, connection} -> connection
      {:error, _} -> raise "Tailscale connection not found"
    end
  end

  # Business Logic Functions

  @doc """
  Syncs connection state from CLI status after external connection.
  """
  def sync_connection_state do
    connection = get_connection!()

    case check_connectivity() do
      {:ok, vpn_info} when is_map(vpn_info) ->
        update_connection(connection, Map.merge(vpn_info, %{
          status: :connected,
          connected_at: DateTime.utc_now(),
          last_checked_at: DateTime.utc_now(),
          last_error: nil,
          last_error_at: nil
        }))

      {:ok, :healthy} ->
        case get_vpn_ip() do
          {:ok, vpn_ip} ->
            update_connection(connection, %{
              status: :connected,
              vpn_ip: vpn_ip,
              connected_at: DateTime.utc_now(),
              last_checked_at: DateTime.utc_now(),
              last_error: nil,
              last_error_at: nil
            })

          {:error, _reason} ->
            update_connection(connection, %{
              status: :connected,
              connected_at: DateTime.utc_now(),
              last_checked_at: DateTime.utc_now(),
              last_error: nil,
              last_error_at: nil
            })
        end

      {:error, reason} ->
        Logger.warning("Tailscale: Failed to sync connection state: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Checks and updates connectivity for an active connection.
  """
  def check_and_update_connectivity do
    connection = get_connection!()

    cond do
      connection.manual_disconnect ->
        Logger.debug("Tailscale: Skipping connectivity check - manual disconnect active")
        :ok

      connection.status == :connected ->
        Logger.debug("Tailscale: Monitoring connection")
        handle_connectivity_check(connection)

      true ->
        Logger.debug("Tailscale: Skipping connectivity check - not connected")
        :ok
    end
  end

  @doc """
  Attempts auto-reconnection if conditions are met.
  """
  def attempt_auto_reconnection(vpn_url, enrollment_key, hostname_provider) do
    connection = get_connection!()

    if should_reconnect?(connection) do
      Logger.info("Tailscale: Attempting auto-reconnection")
      hostname = get_hostname(hostname_provider)

      with {:ok, updated_connection} <- update_connection(connection, %{status: :connecting}),
           {:ok, result} <- connect_to_vpn(vpn_url, enrollment_key, hostname) do
        handle_connection_success(updated_connection, result)
      else
        {:error, reason} -> handle_connection_failure(connection, reason)
      end
    else
      Logger.debug("Tailscale: Skipping auto-reconnection - conditions not met")
      :skipped
    end
  end

  @doc """
  Initiates manual connection.
  """
  def connect_to_vpn_manual(vpn_url, enrollment_key, hostname_provider) do
    Logger.info("Tailscale: Initiating manual connection")
    connection = get_connection!()
    hostname = get_hostname(hostname_provider)

    with {:ok, updated_connection} <- update_connection(connection, %{status: :connecting}),
         {:ok, result} <- connect_to_vpn(vpn_url, enrollment_key, hostname) do
      handle_connection_success(updated_connection, result)
    else
      {:error, reason} -> handle_connection_failure(connection, reason)
    end
  end

  @doc """
  Initiates manual disconnection.
  """
  def disconnect_from_vpn_manual do
    Logger.info("Tailscale: Initiating manual disconnection")
    connection = get_connection!()

    case disconnect_from_vpn() do
      :ok ->
        update_connection(connection, %{
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

  # Private Functions

  defp cli_client do
    Application.get_env(:tailscale, :cli_client, Tailscale.Cli.Client)
  end

  defp api_client do
    Application.get_env(:tailscale, :api_client, Tailscale.Api.Client)
  end

  defp handle_connectivity_check(connection) do
    case check_connectivity() do
      {:ok, vpn_info} when is_map(vpn_info) ->
        update_connection_healthy(connection, vpn_info)
        log_vpn_info_update(vpn_info)
        :ok

      {:ok, :healthy} ->
        update_connection_healthy(connection)
        :ok

      {:error, reason} ->
        update_connection_lost(connection, reason)
    end
  end

  defp handle_connection_success(connection, :no_info) do
    attrs = connection_success_attrs()
    update_and_log(connection, attrs, "Tailscale: Connected successfully")
  end

  defp handle_connection_success(connection, vpn_info) when is_map(vpn_info) do
    attrs = connection_success_attrs(vpn_info)
    message = "Tailscale: Connected successfully - IP: #{vpn_info[:vpn_ip]}, Hostname: #{vpn_info[:vpn_hostname]}"
    update_and_log(connection, attrs, message)
  end

  defp handle_connection_failure(connection, reason) do
    attrs = %{
      status: :disconnected,
      last_error: reason,
      last_error_at: DateTime.utc_now()
    }
    update_and_log(connection, attrs, "Tailscale: Connection failed - #{reason}")
  end

  defp connection_success_attrs(vpn_info \\ %{}) do
    base_attrs = %{
      status: :connected,
      connected_at: DateTime.utc_now(),
      last_error: nil,
      last_error_at: nil
    }
    Map.merge(base_attrs, vpn_info)
  end

  defp update_connection_healthy(connection, vpn_info \\ %{}) do
    attrs = Map.merge(vpn_info, %{
      last_checked_at: DateTime.utc_now(),
      last_error: nil,
      last_error_at: nil
    })

    case update_connection(connection, attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_connection_lost(connection, reason) do
    log_connection_duration(connection)

    attrs = %{
      status: :disconnected,
      vpn_ip: nil,
      vpn_hostname: nil,
      last_error: reason,
      last_error_at: DateTime.utc_now(),
      last_checked_at: DateTime.utc_now()
    }
    update_and_log(connection, attrs, "Tailscale: Connection lost - #{reason}")
  end

  defp update_and_log(connection, attrs, log_message) do
    case update_connection(connection, attrs) do
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

  defp get_hostname(hostname_provider) do
    case hostname_provider do
      fun when is_function(fun, 0) -> fun.()
      {module, function} -> apply(module, function, [])
      {module, function, args} -> apply(module, function, args)
      string when is_binary(string) -> string
    end
  end
end
