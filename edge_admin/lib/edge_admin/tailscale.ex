# edge_admin/lib/edge_admin/tailscale.ex
defmodule EdgeAdmin.Tailscale do
  @moduledoc """
  The Tailscale context for VPN operations.

  This context provides functionality for connecting to and managing
  Tailscale VPN connections using enrollment keys.
  """

  @doc """
  Connects to VPN using enrollment key and returns connection info.
  """
  def connect_to_vpn(vpn_url, enrollment_key, hostname) do
    client().connect_to_vpn(vpn_url, enrollment_key, hostname)
  end

  @doc """
  Checks connectivity and returns current VPN information.
  """
  def check_connectivity do
    client().check_connectivity()
  end

  @doc """
  Disconnects from VPN.
  """
  def disconnect_from_vpn do
    client().disconnect_from_vpn()
  end

  @doc """
  Gets Tailscale status as JSON.
  """
  def status_json do
    client().status_json()
  end

  @doc """
  Checks if Tailscale is connected based on status data.
  """
  def connected?(status_data) do
    client().connected?(status_data)
  end

  @doc """
  Starts the Tailscale daemon.
  """
  def start_daemon do
    client().start_daemon()
  end

  @doc """
  Gets the current VPN IP address.
  """
  def get_vpn_ip do
    client().get_vpn_ip()
  end

  # Private function to get the configured client module
  defp client do
    Application.get_env(:edge_admin, :tailscale_module, EdgeAdmin.Tailscale.Client)
  end
end
