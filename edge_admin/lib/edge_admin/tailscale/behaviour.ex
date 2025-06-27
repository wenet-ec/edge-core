# edge_admin/lib/edge_admin/tailscale/behaviour.ex
defmodule EdgeAdmin.Tailscale.Behaviour do
  @moduledoc """
  Behaviour for Tailscale operations - used for testing and abstraction.

  This provides a unified interface for VPN operations that can be
  mocked during testing and swapped for different implementations.
  """

  @type connection_result :: {:ok, map()} | {:ok, :no_info} | {:error, String.t()}
  @type connectivity_result :: {:ok, map()} | {:ok, :healthy} | {:error, String.t()}

  @callback connect_to_vpn(String.t(), String.t(), String.t()) :: connection_result()
  @callback check_connectivity() :: connectivity_result()
  @callback disconnect_from_vpn() :: :ok | {:error, String.t()}
  @callback status_json() :: {:ok, map()} | {:error, String.t()}
  @callback connected?(map()) :: boolean()
  @callback start_daemon() :: :ok
  @callback get_vpn_ip() :: {:ok, String.t()} | {:error, atom()}
end
