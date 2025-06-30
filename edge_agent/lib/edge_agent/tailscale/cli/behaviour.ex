# edge_agent/lib/edge_agent/tailscale/cli/behaviour.ex
defmodule EdgeAgent.Tailscale.Cli.Behaviour do
  @moduledoc """
  Behaviour for Tailscale CLI operations.

  This behaviour defines the interface for Tailscale command-line operations
  such as connecting, disconnecting, and checking status. It enables easy
  mocking during tests and abstraction of the underlying CLI implementation.
  """

  @type connection_result :: {:ok, map()} | {:ok, :no_info} | {:error, String.t()}
  @type connectivity_result :: {:ok, map()} | {:ok, :healthy} | {:error, String.t()}
  @type status_result :: {:ok, map()} | {:error, String.t()}
  @type vpn_ip_result :: {:ok, String.t()} | {:error, atom()}
  @type disconnect_result :: :ok | {:error, String.t()}

  @doc """
  Connects to VPN using enrollment key and hostname.

  Returns connection information if available, or :no_info if successful
  but no detailed information is available.
  """
  @callback connect_to_vpn(String.t(), String.t(), String.t()) :: connection_result()

  @doc """
  Checks current connectivity status.

  Returns detailed VPN info if available, :healthy if connected but no details,
  or an error if not connected or check fails.
  """
  @callback check_connectivity() :: connectivity_result()

  @doc """
  Disconnects from VPN.
  """
  @callback disconnect_from_vpn() :: disconnect_result()

  @doc """
  Gets Tailscale status as JSON data.
  """
  @callback status_json() :: status_result()

  @doc """
  Checks if currently connected based on status data.
  """
  @callback connected?(map()) :: boolean()

  @doc """
  Starts the Tailscale daemon.
  """
  @callback start_daemon() :: :ok

  @doc """
  Gets the current VPN IP address.
  """
  @callback get_vpn_ip() :: vpn_ip_result()
end
