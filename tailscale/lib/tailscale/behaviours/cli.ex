# tailscale/lib/tailscale/behaviours/cli.ex
defmodule Tailscale.Behaviours.Cli do
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

  @callback connect_to_vpn(String.t(), String.t(), String.t()) :: connection_result()
  @callback check_connectivity() :: connectivity_result()
  @callback disconnect_from_vpn() :: disconnect_result()
  @callback status_json() :: status_result()
  @callback connected?(map()) :: boolean()
  @callback start_daemon() :: :ok
  @callback get_vpn_ip() :: vpn_ip_result()
end