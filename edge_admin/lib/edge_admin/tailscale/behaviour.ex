# edge_admin/lib/edge_admin/tailscale/behaviour.ex
defmodule EdgeAdmin.Tailscale.Behaviour do
  @moduledoc """
  Behaviour for Tailscale operations - used for testing.
  """

  @callback connect_to_vpn(String.t()) :: {:ok, map()} | {:ok, :no_info} | {:error, String.t()}
  @callback check_connectivity() :: {:ok, map()} | {:ok, :healthy} | {:error, String.t()}
  @callback disconnect_from_vpn() :: :ok | {:error, String.t()}
end
