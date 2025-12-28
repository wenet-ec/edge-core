# edge_admin/lib/edge_admin/edge_clusters.ex
defmodule EdgeAdmin.EdgeClusters do
  @moduledoc """
  Gateway coordinator that manages VPN connections to edge clusters.

  This GenServer orchestrates Gateway processes (one per assigned cluster) based on
  metadata assignments. It subscribes to cluster assignment changes and dynamically
  starts/stops Gateway processes to match the current topology.

  ## Key Concepts

  - **Gateway**: A GenServer that maintains VPN connection to a single cluster
  - **Metadata Assignment**: ETS-based mapping of which admin owns which clusters
  - **Reconciliation**: Process of starting/stopping Gateways to match assignments
  - **Anti-Thrashing**: Flag pattern prevents rapid start/stop cycles

  ## Responsibilities

  - Subscribe to metadata recomputation events (`PubSub`)
  - Read cluster assignments from ETS (`Metadata`)
  - Diff old vs new assignments (start/stop logic)
  - Orchestrate Gateway lifecycle via `DynamicSupervisor`
  - Prevent thrashing with reconciliation flag pattern

  ## Architecture

  **Coordinator Pattern**: This module coordinates, `EdgeClusters.Supervisor` supervises:
  - `EdgeClusters` (this module): Coordinator GenServer
  - `EdgeClusters.Supervisor`: DynamicSupervisor for Gateway processes
  - `EdgeClusters.Gateway`: Per-cluster GenServer managing VPN connection

  **Race Condition Handling**: Starts after Metadata but handles timing gracefully:
  - Subscribe to PubSub first
  - Then read ETS immediately
  - Result: Never miss assignments regardless of startup order

  **Anti-Thrashing**: Simple boolean flag prevents rapid reconciliation cycles:
  - If reconciling, set `pending_reconcile: true` (don't interrupt)
  - When done, check flag and reconcile again if needed
  - No locks, timers, or debouncing - just a flag

  ## Examples

      # Coordinator receives metadata event
      {:metadata_recomputed, ...} -> reconcile_gateways()

      # Result: Start Gateway for new cluster
      DynamicSupervisor.start_child(GatewaySupervisor, {Gateway, cluster: "prod"})

      # Result: Stop Gateway for removed cluster
      DynamicSupervisor.terminate_child(GatewaySupervisor, gateway_pid)
  """

  use GenServer

  alias EdgeAdmin.EdgeClusters.Supervisor, as: GatewaySupervisor

  require Logger

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
       # %{cluster_name => pid}
       gateway_pids: %{},
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
    assignments
    |> Map.get(admin_name, %{})
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

      Logger.info("EdgeClusters reconciliation: +#{MapSet.size(to_join)} clusters, -#{MapSet.size(to_leave)} clusters")

      # Track successful joins separately
      successful_joins = MapSet.new()

      # Start tracking new gateway pids
      new_gateway_pids = state.gateway_pids

      # Apply changes (VPN operations happen here - slow)
      {new_gateway_pids, successful_joins} =
        Enum.reduce(to_join, {new_gateway_pids, successful_joins}, fn cluster_name, {acc_pids, acc_joins} ->
          case start_gateway(cluster_name) do
            {:ok, pid} ->
              Logger.info("Successfully started gateway for #{cluster_name}")
              {Map.put(acc_pids, cluster_name, pid), MapSet.put(acc_joins, cluster_name)}

            {:error, reason} ->
              Logger.error(
                "Failed to start gateway for #{cluster_name}: #{inspect(reason)} - will retry on next metadata event"
              )

              {acc_pids, acc_joins}
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

      # Only mark as current if we successfully joined
      # Start with clusters that were already current and not being removed
      new_current_clusters =
        state.current_clusters
        |> MapSet.difference(to_leave)
        |> MapSet.union(successful_joins)

      Logger.debug(
        "EdgeClusters state update: current_clusters=#{inspect(MapSet.to_list(new_current_clusters))}, gateway_pids=#{inspect(Map.keys(new_gateway_pids))}"
      )

      # Update parent state
      send(parent, {:update_clusters, new_current_clusters, new_gateway_pids})

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
