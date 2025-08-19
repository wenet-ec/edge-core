# edge_agent/lib/edge_agent/vpn.ex
defmodule EdgeAgent.VPN do
  @moduledoc """
  VPN context for EdgeAgent.

  This module provides EdgeAgent-specific VPN functionality while delegating
  core operations to the shared Tailscale library. It handles EdgeAgent's
  specific hostname requirements (node-{id}) and Settings integration.
  """

  alias EdgeAgent.Settings

  require Logger

  # Delegate all basic operations to the configurable Tailscale module
  def connect_to_vpn(vpn_url, enrollment_key, hostname),
    do: tailscale_module().connect_to_vpn(vpn_url, enrollment_key, hostname)

  def disconnect_from_vpn, do: tailscale_module().disconnect_from_vpn()
  def check_connectivity, do: tailscale_module().check_connectivity()
  def status_json, do: tailscale_module().status_json()
  def connected?(status_data), do: tailscale_module().connected?(status_data)
  def start_daemon, do: tailscale_module().start_daemon()
  def get_vpn_ip, do: tailscale_module().get_vpn_ip()
  def get_node_by_hostname(vpn_hostname), do: tailscale_module().get_node_by_hostname(vpn_hostname)
  def list_nodes_for_user(user \\ "edge-nodes"), do: tailscale_module().list_nodes_for_user(user)
  def create_enrollment_key(user \\ "edge-nodes"), do: tailscale_module().create_enrollment_key(user)
  def get_user(username), do: tailscale_module().get_user(username)
  def get_connection, do: tailscale_module().get_connection()
  def create_connection(attrs \\ %{}), do: tailscale_module().create_connection(attrs)
  def get_connection!, do: tailscale_module().get_connection!()
  def check_and_update_connectivity, do: tailscale_module().check_and_update_connectivity()
  def sync_connection_state, do: tailscale_module().sync_connection_state()

  # Get the configurable Tailscale module
  defp tailscale_module do
    Application.get_env(:edge_agent, :tailscale_module, Tailscale)
  end

  # EdgeAgent-specific hostname provider function
  defp hostname_provider do
    fn ->
      case Settings.get("id") do
        {:ok, node_id} -> "node-#{node_id}"
        {:error, _} -> "edge-agent-unknown"
      end
    end
  end

  # EdgeAgent-specific business logic functions

  def update_connection(attrs) do
    connection = get_connection!()
    tailscale_module().update_connection(connection, attrs)
  end

  def attempt_auto_reconnection do
    tailscale_module().attempt_auto_reconnection(vpn_url(), enrollment_key(), hostname_provider())
  end

  def connect_to_vpn_manual do
    tailscale_module().connect_to_vpn_manual(vpn_url(), enrollment_key(), hostname_provider())
  end

  def disconnect_from_vpn_manual, do: tailscale_module().disconnect_from_vpn_manual()

  # Private helper functions

  defp vpn_url do
    System.get_env("VPN_URL") || raise "VPN_URL environment variable not set"
  end

  defp enrollment_key do
    System.get_env("ENROLLMENT_KEY") || raise "ENROLLMENT_KEY environment variable not set"
  end
end
