# edge_admin/lib/edge_admin/vpn.ex
defmodule EdgeAdmin.VPN do
  @moduledoc """
  VPN context for EdgeAdmin.
  
  This module provides EdgeAdmin-specific VPN functionality while delegating
  core operations to the shared Tailscale library. It handles EdgeAdmin's
  specific hostname requirements, environment configuration, and business logic.
  """

  alias Tailscale.Connection
  require Logger

  # Delegate all basic operations to the shared library
  defdelegate connect_to_vpn(vpn_url, enrollment_key, hostname), to: Tailscale
  defdelegate disconnect_from_vpn(), to: Tailscale
  defdelegate check_connectivity(), to: Tailscale
  defdelegate status_json(), to: Tailscale
  defdelegate connected?(status_data), to: Tailscale
  defdelegate start_daemon(), to: Tailscale
  defdelegate get_vpn_ip(), to: Tailscale
  defdelegate get_node_by_hostname(vpn_hostname), to: Tailscale
  defdelegate list_nodes_for_user(user \\ "edge-nodes"), to: Tailscale
  defdelegate create_enrollment_key(user \\ "edge-nodes"), to: Tailscale
  defdelegate get_user(username), to: Tailscale
  defdelegate get_connection(), to: Tailscale
  defdelegate create_connection(attrs \\ %{}), to: Tailscale
  defdelegate get_connection!(), to: Tailscale
  defdelegate check_and_update_connectivity(), to: Tailscale
  defdelegate sync_connection_state(), to: Tailscale
  defdelegate disconnect_from_vpn_manual(), to: Tailscale

  # EdgeAdmin-specific hostname provider
  defp hostname_provider, do: "edge-admin"

  # EdgeAdmin-specific business logic functions

  @doc """
  Updates the VPN connection with the given attributes.
  """
  def update_connection(attrs) do
    connection = get_connection!()
    Tailscale.update_connection(connection, attrs)
  end

  @doc """
  Updates VPN connection from controller parameters with validation.
  
  This function handles parameter validation and business logic for VPN connection updates.
  """
  def update_connection_from_params(%{"manual_disconnect" => manual_disconnect} = _params) 
      when is_boolean(manual_disconnect) do
    update_connection_manual_disconnect(manual_disconnect)
  end

  def update_connection_from_params(_params) do
    {:error, :invalid_params}
  end

  @doc """
  Updates the VPN connection with manual disconnect handling.
  
  This function encapsulates the business logic for updating VPN connections:
  - When manual_disconnect is true: Performs immediate disconnect
  - When manual_disconnect is false: Updates flag to allow auto-reconnection
  """
  def update_connection_manual_disconnect(manual_disconnect) when is_boolean(manual_disconnect) do
    case manual_disconnect do
      true ->
        Logger.info("VPN: Performing manual disconnect")
        disconnect_from_vpn_manual()
        
      false ->
        Logger.info("VPN: Re-enabling auto-reconnection")
        update_connection(%{manual_disconnect: false})
    end
  end

  @doc """
  Attempts auto-reconnection using EdgeAdmin-specific configuration.
  """
  def attempt_auto_reconnection do
    Tailscale.attempt_auto_reconnection(vpn_url(), enrollment_key(), hostname_provider())
  end

  @doc """
  Initiates manual connection using EdgeAdmin-specific configuration.
  """
  def connect_to_vpn_manual do
    Tailscale.connect_to_vpn_manual(vpn_url(), enrollment_key(), hostname_provider())
  end

  @doc """
  Creates enrollment key with proper error handling and user-friendly messages.
  
  This function encapsulates the business logic for enrollment key creation including
  error classification and message formatting.
  """
  def create_enrollment_key_with_error_handling do
    case create_enrollment_key() do
      {:ok, enrollment_data} ->
        {:ok, enrollment_data}

      {:error, :vpn_service_unavailable} ->
        {:error, :vpn_service_unavailable, "VPN service is currently unavailable"}

      {:error, :user_not_found} ->
        {:error, :internal_server_error, "edge-nodes user not found in VPN system"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Connection data transformation
  
  @doc """
  Transforms a Tailscale.Connection struct into a map suitable for JSON rendering.
  """
  def connection_to_map(%Connection{} = connection) do
    %{
      status: connection.status,
      vpn_ip: connection.vpn_ip,
      vpn_hostname: connection.vpn_hostname,
      connected_at: connection.connected_at,
      last_checked_at: connection.last_checked_at,
      last_error: connection.last_error,
      last_error_at: connection.last_error_at,
      manual_disconnect: connection.manual_disconnect,
      inserted_at: connection.inserted_at,
      updated_at: connection.updated_at
    }
  end

  # Private helper functions

  defp vpn_url do
    System.get_env("VPN_URL") || raise "VPN_URL environment variable not set"
  end

  defp enrollment_key do
    System.get_env("ENROLLMENT_KEY") || raise "ENROLLMENT_KEY environment variable not set"
  end
end