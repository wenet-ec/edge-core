defmodule EdgeAgent.EdgeClusters.Relay do
  @moduledoc """
  Manages relay node assignments for the agent.

  This module handles relay node registration logic. The worker calls this module
  only when relay is enabled AND VPN admin URLs are available.

  ## How It Works

  1. Check if relay_admin_name is nil -> create relayed node
  2. If relay_admin_name exists, ping to check if still connected
  3. If relay admin not found in ping OR connected=false -> create relayed node
  4. If relay admin still connected -> do nothing

  ## VPN Requirement

  Relay assignment REQUIRES VPN connectivity to admins. This module uses
  `AdminClient.create_relayed_node(fallback_enabled: false)` to ensure
  relay requests only go through VPN-discovered admin URLs, not HTTP fallback.

  ## Trust Model

  - **Discovery worker validates admins** - Only reachable admins are in `admin_urls`
  - **AdminClient tries each admin** - Tries each VPN admin URL until one succeeds
  - **Ping checks relay health** - Ensures current relay is still reachable
  - **Last write wins** - Only the most recent relay assignment matters

  ## Idempotency

  This module is designed to be idempotent and can be called repeatedly:
  - If relay admin still connected, does nothing
  - If relay admin disconnected, requests new assignment
  - Safe to run every minute without side effects
  """

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings
  alias Nexmaker.Cli

  require Logger

  @doc """
  Checks relay health and registers if needed.

  This is the main entry point called by the RegisterRelayedNodeWorker.
  Worker ensures this is only called when relay is enabled and VPN admin URLs exist.
  """
  @spec check_and_register() :: :ok
  def check_and_register do
    current_relay = Settings.get_relay_admin_name()

    if is_nil(current_relay) or current_relay == "" do
      # No relay assigned yet - create one
      Logger.info("No relay assigned, creating relayed node")
      create_and_store_relay()
    else
      # Check if current relay is still connected
      case Cli.ping_peers() do
        {:ok, ping_data} ->
          check_relay_health(ping_data, current_relay)

        {:error, reason} ->
          Logger.error("Failed to ping peers: #{inspect(reason)}, creating new relay")
          create_and_store_relay()
      end
    end
  end

  defp check_relay_health(ping_data, current_relay) do
    # Find relay admin in ping results
    # Ping data format: %{"cluster-default" => [%{"name" => "admin-xyz", "connected" => true, ...}]}
    relay_peer =
      ping_data
      |> Enum.flat_map(fn {_network, peers} -> peers end)
      |> Enum.find(fn peer -> peer["name"] == current_relay end)

    cond do
      # Relay not found in ping results (unreachable)
      is_nil(relay_peer) ->
        Logger.warning("Relay admin #{current_relay} not reachable via ping, registering new relay")

        :telemetry.execute(
          [:edge_agent, :relay, :health_check],
          %{count: 1},
          %{status: :not_found}
        )

        create_and_store_relay()

      # Relay found but not connected
      not relay_peer["connected"] ->
        Logger.warning("Relay admin #{current_relay} not connected (latency check failed), registering new relay")

        :telemetry.execute(
          [:edge_agent, :relay, :health_check],
          %{count: 1},
          %{status: :disconnected}
        )

        create_and_store_relay()

      # Relay still connected
      true ->
        Logger.debug("Relay admin #{current_relay} still connected (latency: #{relay_peer["latency_ms"]}ms)")

        :telemetry.execute(
          [:edge_agent, :relay, :health_check],
          %{count: 1},
          %{status: :connected}
        )

        :ok
    end
  end

  defp create_and_store_relay do
    # Get current relay to detect failover
    old_relay = Settings.get_relay_admin_name()

    # IMPORTANT: Relay requires VPN - disable HTTP fallback
    case AdminClient.create_relayed_node(fallback_enabled: false) do
      {:ok, %{"data" => %{"relay_admin_name" => relay_admin_name}}} ->
        Settings.set_relay_admin_name(relay_admin_name)
        Logger.info("Successfully register to relay admin: #{relay_admin_name}")

        # Track if this is a failover (relay admin changed)
        failover_count = if old_relay && old_relay != "" && old_relay != relay_admin_name, do: 1, else: 0

        :telemetry.execute(
          [:edge_agent, :relay, :assignment],
          %{count: 1, failover_count: failover_count},
          %{status: :success}
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to register relayed node: #{inspect(reason)}")

        :telemetry.execute(
          [:edge_agent, :relay, :assignment],
          %{count: 1, failover_count: 0},
          %{status: :error}
        )

        :ok
    end
  end
end
