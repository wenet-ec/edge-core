# edge_admin/lib/edge_admin/vpn/cli.ex
defmodule EdgeAdmin.Vpn.Cli do
  @moduledoc "Local Edge VPN CLI operations used by the Admin."

  @spec read_local_vpn_nodes() :: {:ok, [map()]} | {:error, term()}
  def read_local_vpn_nodes, do: Nexmaker.Cli.read_nodes()

  @spec read_local_vpn_host_id() :: {:ok, String.t()} | {:error, term()}
  def read_local_vpn_host_id, do: Nexmaker.Cli.read_host_id()

  @spec join_network(keyword()) :: {:ok, map()} | {:error, term()}
  def join_network(opts), do: Nexmaker.Cli.join_network(opts)

  @spec health_check(keyword()) :: {:ok, :healthy | :degraded | :unhealthy, map()}
  def health_check(opts \\ []), do: Nexmaker.Cli.health_check(opts)

  @spec pull_vpn_config() :: :ok | {:error, term()}
  def pull_vpn_config do
    if Application.get_env(:edge_admin, :vpn_config_pull_enabled, true) do
      Nexmaker.Cli.pull()
    else
      :ok
    end
  end
end
