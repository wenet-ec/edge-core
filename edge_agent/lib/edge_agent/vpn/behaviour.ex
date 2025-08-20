# edge_agent/lib/edge_agent/vpn/behaviour.ex
defmodule EdgeAgent.VPN.Behaviour do
  @moduledoc """
  Behaviour defining the VPN interface for EdgeAgent.
  Allows mocking of VPN operations during testing.
  """

  @callback start_daemon() :: :ok | {:error, term()}
  @callback connect_to_vpn(String.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  @callback get_vpn_ip() :: {:ok, String.t()} | {:error, term()}
  @callback sync_connection_state() :: {:ok, term()} | {:error, term()}
  @callback disconnect_from_vpn() :: :ok | {:error, term()}
  @callback check_connectivity() :: {:ok, term()} | {:error, term()}
end
