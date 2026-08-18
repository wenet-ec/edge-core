# edge_admin/lib/edge_admin/gateway_registry/coordinator.ex
defmodule EdgeAdmin.GatewayRegistry.Coordinator do
  @moduledoc """
  Gateway coordinator that manages VPN connections to edge clusters.

  This GenServer subscribes to local metadata recomputation events, reads this
  Admin's assigned clusters from ETS, and starts/stops one Gateway process per
  assigned cluster through `GatewayRegistry.Supervisor`.

  **Race Condition Handling**: `init/1` only subscribes to local metadata events
  and starts with an empty `current_clusters` set — it does NOT pre-load ETS
  assignments. This is safe because `Metadata.init/1` always runs an initial
  recomputation that broadcasts `:metadata_recomputed` once it completes, which
  triggers our first reconciliation. So no matter the startup order between
  `Metadata` and `GatewayRegistry`, the first event is never missed.

  **Anti-Thrashing**: Simple boolean flag prevents rapid reconciliation cycles:
  - If reconciling, set `pending_reconcile: true` (don't interrupt)
  - When done, check flag and reconcile again if needed
  - No locks, timers, or debouncing - just a flag
  """

  use GenServer

  alias EdgeAdmin.AdminClustering.Metadata
  alias EdgeAdmin.GatewayRegistry.Reconciler
  alias EdgeAdmin.GatewayRegistry.Supervisor, as: GatewaySupervisor
  alias EdgeAdmin.Vpn

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :syn.add_node_to_scopes([:cluster_scope])

    admin_name = Application.get_env(:edge_admin, :admin_name)
    Metadata.Events.subscribe_local()

    Logger.info("GatewayRegistry coordinator subscribed to local metadata events, waiting")

    {:ok,
     %{
       admin_name: admin_name,
       current_clusters: MapSet.new(),
       gateway_pids: %{},
       reconciling?: false,
       pending_reconcile: false
     }}
  end

  @impl true
  def handle_info(:metadata_recomputed, state) do
    if state.reconciling? do
      Logger.debug("GatewayRegistry coordinator: Metadata changed while reconciling, marked pending")
      {:noreply, %{state | pending_reconcile: true}}
    else
      spawn_reconciliation_task(state)
      Logger.debug("GatewayRegistry coordinator: Starting reconciliation")
      {:noreply, %{state | reconciling?: true}}
    end
  end

  @impl true
  def handle_info(:reconciliation_complete, state) do
    if state.pending_reconcile do
      spawn_reconciliation_task(state)
      Logger.debug("GatewayRegistry coordinator: Pending reconciliation triggered")
      {:noreply, %{state | reconciling?: true, pending_reconcile: false}}
    else
      Logger.debug("GatewayRegistry coordinator: Reconciliation complete, idle")
      {:noreply, %{state | reconciling?: false}}
    end
  end

  @impl true
  def handle_info({:update_clusters, new_clusters_set, new_gateway_pids}, state) do
    :telemetry.execute(
      [:edge_admin, :gateway, :active_count],
      %{active_count: map_size(new_gateway_pids)},
      %{}
    )

    {:noreply, %{state | current_clusters: new_clusters_set, gateway_pids: new_gateway_pids}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("GatewayRegistry coordinator received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp get_assigned_clusters(admin_name) do
    assignments = Metadata.get_edge_clusters()

    assignments
    |> Map.get(admin_name, %{})
    |> Map.keys()
  end

  defp spawn_reconciliation_task(state) do
    parent = self()

    Task.start(fn ->
      new_clusters = get_assigned_clusters(state.admin_name)
      new_clusters_set = MapSet.new(new_clusters)

      reconciliation = Reconciler.plan(state.current_clusters, new_clusters_set)
      to_join = reconciliation.to_join
      to_leave = reconciliation.to_leave

      Logger.info(
        "GatewayRegistry reconciliation: +#{MapSet.size(to_join)} clusters, -#{MapSet.size(to_leave)} clusters"
      )

      successful_joins = MapSet.new()
      new_gateway_pids = state.gateway_pids

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

      sweep_unassigned_vpn_memberships(new_clusters_set)

      # Only mark a new assignment current after the Gateway actually starts.
      new_current_clusters =
        state.current_clusters
        |> MapSet.difference(to_leave)
        |> MapSet.union(successful_joins)

      Logger.debug(
        "GatewayRegistry state update: current_clusters=#{inspect(MapSet.to_list(new_current_clusters))}, gateway_pids=#{inspect(Map.keys(new_gateway_pids))}"
      )

      send(parent, {:update_clusters, new_current_clusters, new_gateway_pids})
      send(parent, :reconciliation_complete)
    end)
  end

  defp start_gateway(cluster_name) do
    Logger.info("Starting Gateway for cluster #{cluster_name}")

    child_spec = %{
      id: {:gateway, cluster_name},
      start: {EdgeAdmin.GatewayRegistry.VirtualGateway, :start_link, [cluster_name]},
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
    end
  end

  defp sweep_unassigned_vpn_memberships(assigned_clusters) do
    vpn_host_id = Metadata.get_admin().vpn_host_id

    case Vpn.edge_vpn_cli_health_check() do
      {:ok, _status, %{networks: networks}} when is_list(networks) ->
        networks
        |> Enum.filter(&edge_cluster_network?/1)
        |> Enum.reject(&MapSet.member?(assigned_clusters, &1))
        |> Enum.each(&remove_unassigned_vpn_membership(vpn_host_id, &1))
    end
  end

  defp edge_cluster_network?(network_name) when is_binary(network_name) do
    String.starts_with?(network_name, "cluster-")
  end

  defp edge_cluster_network?(_network_name), do: false

  defp remove_unassigned_vpn_membership(vpn_host_id, cluster_name) do
    Logger.warning("Removing unassigned Edge VPN membership for #{cluster_name}")

    case Vpn.remove_host_from_network(vpn_host_id, cluster_name) do
      {:ok, _} ->
        Logger.info("Removed unassigned Edge VPN membership for #{cluster_name}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to remove unassigned Edge VPN membership for #{cluster_name}: #{inspect(reason)}")

        :ok
    end
  end
end
