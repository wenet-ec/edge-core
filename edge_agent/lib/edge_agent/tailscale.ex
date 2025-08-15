# edge_agent/lib/edge_agent/tailscale.ex
defmodule EdgeAgent.Tailscale do
  @moduledoc """
  EdgeAgent adapter for the shared Tailscale library.

  This module provides EdgeAgent-specific functionality while delegating
  core operations to the shared Tailscale library. It handles EdgeAgent's
  specific hostname requirements (node-{id}) and Settings integration.
  """

  alias EdgeAgent.Settings
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
    Tailscale.update_connection(connection, attrs)
  end

  def attempt_auto_reconnection do
    Tailscale.attempt_auto_reconnection(vpn_url(), enrollment_key(), hostname_provider())
  end

  def connect_to_vpn_manual do
    Tailscale.connect_to_vpn_manual(vpn_url(), enrollment_key(), hostname_provider())
  end

  defdelegate disconnect_from_vpn_manual(), to: Tailscale

  # Private helper functions

  defp vpn_url do
    System.get_env("VPN_URL") || raise "VPN_URL environment variable not set"
  end

  defp enrollment_key do
    System.get_env("ENROLLMENT_KEY") || raise "ENROLLMENT_KEY environment variable not set"
  end

end
