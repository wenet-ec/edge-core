# edge_agent/lib/edge_agent/vpn/vpn.ex
defmodule EdgeAgent.Vpn do
  @moduledoc """
  VPN network operations for the edge agent.

  Handles joining the Netmaker VPN network and verifying connection health.
  The netmaker_key is expected to already be in Settings (written by
  `EdgeAgent.EnrollmentKey.ensure_verified/0` during bootstrap).

  ## Configuration

  - `AGENT_WIREGUARD_PORT` - Static WireGuard port (optional, dynamic if unset)
  - `VPN_READY_TIMEOUT_SECONDS` - Connection verify timeout in seconds (default: 30)
  """

  alias EdgeAgent.Settings

  require Logger

  @doc """
  Pulls latest VPN configuration from Netmaker server.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec pull() :: :ok | {:error, any()}
  def pull do
    Nexmaker.Cli.pull()
  end

  @doc """
  Lists all networks this host is connected to.

  Returns `{:ok, networks}` or `{:error, reason}`.
  """
  @spec list_networks() :: {:ok, [map()]} | {:error, any()}
  def list_networks do
    Nexmaker.Cli.list_networks()
  end

  @doc """
  Pings peers across networks to check connectivity.

  Returns `{:ok, ping_results}` or `{:error, reason}`.
  """
  @spec ping_peers(keyword()) :: {:ok, map()} | {:error, any()}
  def ping_peers(opts \\ []) do
    Nexmaker.Cli.ping_peers(opts)
  end

  @doc """
  Checks netclient VPN connection health.

  Returns `{:ok, status, info}` where status is `:healthy`, `:degraded`, or `:unhealthy`.
  """
  @spec netclient_health_check(keyword()) :: {:ok, :healthy | :degraded | :unhealthy, map()}
  def netclient_health_check(opts \\ []) do
    Nexmaker.Cli.health_check(opts)
  end

  @doc """
  Joins the VPN network if not already connected.

  Checks health first. If already connected (healthy or degraded), returns `:ok`
  immediately. If disconnected, reads the netmaker_key from Settings and joins.
  """
  @spec join_if_needed(String.t()) :: :ok | {:error, String.t()}
  def join_if_needed(node_id) do
    Logger.info("Checking VPN connection status...")

    case health_check() do
      :connected ->
        Logger.info("Already connected to VPN, skipping join")
        :ok

      :disconnected ->
        Logger.info("Not connected to VPN, joining...")
        join_with_stored_key(node_id)
    end
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp join_with_stored_key(node_id) do
    case Settings.get_netmaker_key() do
      nil ->
        {:error, "No netmaker_key in Settings — enrollment may not have completed"}

      netmaker_key ->
        do_join(node_id, netmaker_key)
    end
  end

  defp do_join(node_id, netmaker_key) do
    node_name = "node-#{node_id}"
    agent_wireguard_port = Application.get_env(:edge_agent, :agent_wireguard_port)

    join_opts =
      case agent_wireguard_port do
        nil ->
          Logger.info("Joining VPN as #{node_name} (dynamic port)...")
          [token: netmaker_key, name: node_name]

        port when is_integer(port) ->
          Logger.info("Joining VPN as #{node_name} (WireGuard port: #{port})...")
          [token: netmaker_key, name: node_name, port: port, static_port: true]
      end

    with {:ok, _} <- Nexmaker.Cli.join_network(join_opts),
         :ok <- verify_connection_after_join() do
      Logger.info("Successfully joined VPN network")
      :ok
    else
      {:error, reason} -> {:error, "VPN join failed: #{inspect(reason)}"}
    end
  end

  defp health_check do
    # Nexmaker.Cli.health_check/0 maps every internal failure to
    # `{:ok, :unhealthy, _}`, so it never returns `{:error, _}`. No defensive
    # error clause is needed here.
    case Nexmaker.Cli.health_check() do
      {:ok, :healthy, _} -> :connected
      {:ok, :degraded, _} -> :connected
      {:ok, :unhealthy, _} -> :disconnected
    end
  end

  defp verify_connection_after_join do
    timeout_seconds = Application.get_env(:edge_agent, :vpn_ready_timeout_seconds, 30)
    Logger.info("Verifying VPN connection (timeout: #{timeout_seconds}s)...")
    verify_with_retry(System.monotonic_time(:second) + timeout_seconds, 2)
  end

  defp verify_with_retry(deadline, interval) do
    remaining = deadline - System.monotonic_time(:second)

    if remaining <= 0 do
      {:error, "VPN join verification timed out: not connected to any network"}
    else
      Process.sleep(min(interval, remaining) * 1000)

      case Nexmaker.Cli.health_check() do
        {:ok, :healthy, info} ->
          Logger.info("VPN connection verified: joined #{length(info[:networks] || [])} network(s)")
          :ok

        {:ok, :degraded, info} ->
          networks = info[:networks] || []

          if length(networks) > 0 do
            Logger.warning("VPN connected but degraded: #{inspect(info[:warnings] || [])}")
            :ok
          else
            Logger.debug("VPN degraded, no networks yet (#{remaining}s remaining)")
            verify_with_retry(deadline, trunc(min(interval * 1.5, 30)))
          end

        {:ok, :unhealthy, info} ->
          Logger.debug("VPN unhealthy (#{remaining}s remaining): #{inspect(info[:warnings] || [])}")
          verify_with_retry(deadline, trunc(min(interval * 1.5, 30)))
      end
    end
  end
end
