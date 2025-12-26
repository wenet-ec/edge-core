# edge_admin/lib/edge_admin/edge_clusters.ex
defmodule EdgeAdmin.EdgeClusters do
  @moduledoc """
  Coordinator GenServer that manages Gateway processes lifecycle.

  Responsibilities:
  - Subscribes to metadata recomputation events
  - Reads ETS to discover cluster assignments
  - Diffs old vs new assignments
  - Orchestrates Gateway start/stop via DynamicSupervisor
  - Prevents thrashing with reconciliation flag pattern

  ## Architecture

  This GenServer coordinates with EdgeAdmin.EdgeClusters.Supervisor (DynamicSupervisor)
  which actually supervises the Gateway processes.

  ## Initialization Race Condition Handling

  The coordinator starts after Metadata in application.ex, but there's a potential
  race condition where Metadata computes and broadcasts before we subscribe.

  Solution: Subscribe to PubSub, then immediately read ETS. This ensures we never
  miss assignments regardless of timing:
  - If Metadata computed first → We read ETS and see assignments
  - If we start first → ETS empty, we wait for first broadcast

  ## Reconciliation Pattern

  Uses simple boolean flag to prevent Gateway thrashing:
  - If reconciling, set `pending_reconcile: true` (don't interrupt)
  - When done, check flag and reconcile again if needed
  - No locks, timers, or debouncing - just a flag
  """

  use GenServer
  require Logger

  alias EdgeAdmin.EdgeClusters.Supervisor, as: GatewaySupervisor

  # ===========================================================================
  # Client API
  # ===========================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(_opts) do
    :syn.add_node_to_scopes([:cluster_scope])

    # Get admin name from Application config
    admin_name = Application.get_env(:edge_admin, :admin_name)

    # Subscribe to local metadata events
    topic = "#{admin_name}:metadata"
    Phoenix.PubSub.subscribe(EdgeAdmin.PubSub, topic)

    Logger.info("EdgeClusters subscribed to #{topic}, waiting for metadata events")

    # Start with empty state - gateways will be spawned when we receive first event
    {:ok,
     %{
       admin_name: admin_name,
       current_clusters: MapSet.new(),
       gateway_pids: %{},  # %{cluster_name => pid}
       reconciling?: false,
       pending_reconcile: false
     }}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_info(:metadata_recomputed, state) do
    if state.reconciling? do
      # Currently working - mark as "needs redo"
      Logger.debug("EdgeClusters: Metadata changed while reconciling, marked pending")
      {:noreply, %{state | pending_reconcile: true}}
    else
      # Idle - start reconciliation
      spawn_reconciliation_task(state)
      Logger.debug("EdgeClusters: Starting reconciliation")
      {:noreply, %{state | reconciling?: true}}
    end
  end

  @impl true
  def handle_info(:reconciliation_complete, state) do
    # Trigger netclient pull to ensure WireGuard interface is consistent
    # This fixes race conditions when multiple networks are joined/left rapidly via MQTT
    case Nexmaker.Cli.pull() do
      :ok ->
        Logger.debug("EdgeClusters: Netclient pull completed successfully")

      {:error, reason} ->
        Logger.warning("EdgeClusters: Netclient pull failed: #{inspect(reason)}")
    end

    if state.pending_reconcile do
      # Something changed while we worked - do it again
      spawn_reconciliation_task(state)
      Logger.debug("EdgeClusters: Pending reconciliation triggered")
      {:noreply, %{state | reconciling?: true, pending_reconcile: false}}
    else
      Logger.debug("EdgeClusters: Reconciliation complete, idle")
      {:noreply, %{state | reconciling?: false}}
    end
  end

  @impl true
  def handle_info({:update_clusters, new_clusters_set, new_gateway_pids}, state) do
    {:noreply, %{state | current_clusters: new_clusters_set, gateway_pids: new_gateway_pids}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("EdgeClusters received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_assigned_clusters(admin_name) do
    # Get assignments from Metadata public API
    assignments = EdgeAdmin.Admins.Metadata.get_edge_clusters()

    # Extract cluster IDs for this admin (keyed by admin_name, not admin_id)
    Map.get(assignments, admin_name, %{})
    |> Map.keys()
  end

  defp spawn_reconciliation_task(state) do
    parent = self()

    Task.start(fn ->
      # Read ETS for new desired state
      new_clusters = get_assigned_clusters(state.admin_name)
      new_clusters_set = MapSet.new(new_clusters)

      # Diff: old vs new
      to_join = MapSet.difference(new_clusters_set, state.current_clusters)
      to_leave = MapSet.difference(state.current_clusters, new_clusters_set)

      Logger.info(
        "EdgeClusters reconciliation: +#{MapSet.size(to_join)} clusters, -#{MapSet.size(to_leave)} clusters"
      )

      # Start tracking new gateway pids
      new_gateway_pids = state.gateway_pids

      # Apply changes (VPN operations happen here - slow)
      new_gateway_pids =
        Enum.reduce(to_join, new_gateway_pids, fn cluster_name, acc ->
          case start_gateway(cluster_name) do
            {:ok, pid} -> Map.put(acc, cluster_name, pid)
            _ -> acc
          end
        end)

      new_gateway_pids =
        Enum.reduce(to_leave, new_gateway_pids, fn cluster_name, acc ->
          case Map.get(acc, cluster_name) do
            nil ->
              Logger.warning("Gateway pid not found for cluster #{cluster_name}")
              acc

            pid ->
              stop_gateway(pid, cluster_name)
              Map.delete(acc, cluster_name)
          end
        end)

      # Update parent state
      send(parent, {:update_clusters, new_clusters_set, new_gateway_pids})

      # Notify completion
      send(parent, :reconciliation_complete)
    end)
  end

  defp start_gateway(cluster_name) do
    Logger.info("Starting Gateway for cluster #{cluster_name}")

    child_spec = %{
      id: {:gateway, cluster_name},
      start: {EdgeAdmin.EdgeClusters.Gateway, :start_link, [cluster_name]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(GatewaySupervisor, child_spec) do
      {:ok, pid} ->
        Logger.info("Gateway started for cluster #{cluster_name}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Gateway already running for cluster #{cluster_name}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Gateway for cluster #{cluster_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp stop_gateway(pid, cluster_name) do
    Logger.info("Stopping Gateway for cluster #{cluster_name}, pid: #{inspect(pid)}")

    result = DynamicSupervisor.terminate_child(GatewaySupervisor, pid)
    Logger.info("terminate_child result: #{inspect(result)}")

    case result do
      :ok ->
        Logger.info("Gateway stopped for cluster #{cluster_name}")
        :ok

      {:error, :not_found} ->
        Logger.debug("Gateway already stopped for cluster #{cluster_name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to stop Gateway for cluster #{cluster_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
