# edge_admin/lib/edge_admin/admins/metadata.ex
defmodule EdgeAdmin.Admins.Metadata do
  @moduledoc """
  Distributed metadata coordinator for admin cluster state and edge cluster assignments.

  This GenServer maintains a distributed ETS table containing the current state of the
  admin cluster topology and cluster assignment decisions. It recomputes assignments
  when topology or edge cluster state changes, broadcasting updates to all admins.

  ## Key Concepts

  - **Metadata**: Distributed state shared across all admins via ETS + replication
  - **Admin Topology**: Which admins exist, their capacity, and health status
  - **Cluster Assignments**: Which admin owns which edge clusters
  - **Recomputation**: Algorithm that redistributes clusters when topology changes
  - **Anti-Thrashing**: Flag pattern prevents rapid recomputation cycles

  ## Responsibilities

  1. **ETS Table Management**
     - Create and own `:metadata` ETS table
     - Provide public read API for queries
     - Update table atomically during recomputations

  2. **Event Subscription**
     - Syn: Admin join/leave events via `SynEventHandler` callback bridge
     - PubSub: Cluster/node CRUD events (PostgreSQL changes)
     - Triggers recomputation when relevant changes occur

  3. **Recomputation Orchestration**
     - Detect when recomputation needed
     - Spawn async task to run Algorithm
     - Update ETS with new assignments
     - Broadcast completion to other admins

  4. **State Machine**
     - `recomputing?: false` - Idle, ready for events
     - `recomputing?: true, pending_recompute: false` - Computing
     - `recomputing?: true, pending_recompute: true` - Computing, redo queued

  ## ETS Schema

  The `:metadata` table contains 4 keys:

  ### `:admin` - This Admin's Info
  ```elixir
  %{
    id: "abc123",
    name: "admin-abc123",
    max_capacity: 200,
    erlang_node_name: :"admin@admin-abc123.admin-cluster-1.nm.internal",
    vpn_hostname: "admin-abc123.admin-cluster-1.nm.internal",
    admin_cluster_name: "admin-cluster-1",
    netmaker_host_id: "95e2707e-...",
    last_computed_at: ~U[2025-01-15 12:00:00Z]
  }
  ```

  ### `:admin_cluster` - Full Topology
  ```elixir
  %{
    name: "admin-cluster-1",
    total_admins: 2,
    total_nodes: 5,      # total nodes across all clusters in the system
    total_capacity: 500, # sum of max_capacity across all admins
    degraded: false,     # true when total_nodes > total_capacity
    topology: [
      %{name: "admin-abc123", max_capacity: 200, vpn_hostname: ...,
        erlang_node_name: ..., netmaker_host_id: "..."},
      %{name: "admin-def456", max_capacity: 300, ...}
    ]
  }
  ```

  ### `:edge_clusters` - Assignment Map
  ```elixir
  %{
    "admin-abc123" => %{
      "cluster-a" => ["node-1", "node-2"],
      "cluster-b" => []
    },
    "admin-def456" => %{
      "cluster-c" => ["node-3"]
    }
  }
  ```

  ### `:orphaned_clusters` - Unassigned Clusters
  ```elixir
  %{
    "cluster-orphaned-1" => ["node-5", "node-6"],
    "cluster-orphaned-2" => ["node-7"]
  }
  ```

  ## Recomputation Triggers

  - Admin joins/leaves (syn event via `SynEventHandler` callback → `{:syn_admin_topology_changed}`)
  - Cluster created/deleted (PubSub event)
  - Node created/deleted (PubSub event)
  - Node cluster changed (PubSub event)
  - Periodic scheduler (every minute via LocalScheduler, safety net)
  - Manual call via `recompute_now/0`

  ## Anti-Thrashing Pattern

  Uses simple boolean flags to prevent rapid recomputation cycles:
  - If recomputing, set `pending_recompute: true` (don't interrupt)
  - When done, check flag and recompute again if needed
  - No locks, timers, or debouncing - just flags

  ## Public API

  All query functions are safe to call from any process (ETS reads are concurrent):
  - `get_admin/0` - This admin's info
  - `get_admin_cluster/0` - Full topology
  - `get_my_clusters/0` - Clusters assigned to this admin
  - `get_cluster_owner/1` - Which admin owns a cluster
  - `find_node_cluster/1` - Which cluster contains a node

  ## Examples

      # Query metadata (from any process)
      iex> Metadata.get_my_clusters()
      %{"cluster-prod" => ["node-1", "node-2"], "cluster-dev" => []}

      # Trigger recomputation (from PubSub event)
      send(Metadata, {:cluster_created, cluster_id})

      # Result: Algorithm runs, assignments updated, broadcast sent
  """

  use GenServer

  alias EdgeAdmin.Admins.Metadata.Algorithm
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Vpn

  require Logger

  @callback degraded?() :: boolean()

  @table :metadata

  # === Lifecycle ===

  @doc """
  Starts the Metadata GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    admin_id = Application.get_env(:edge_admin, :admin_id)
    admin_name = Application.get_env(:edge_admin, :admin_name)
    admin_cluster_name = Application.get_env(:edge_admin, :admin_cluster_name)
    max_capacity = Application.get_env(:edge_admin, :admin_max_capacity)

    Logger.info("Metadata initializing for admin #{admin_name}")

    # Create ETS table
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

    # Compute derived values
    vpn_hostname = Vpn.build_vpn_hostname(admin_name, admin_cluster_name)
    erlang_node_name = node()

    # Fetch Netmaker host ID
    {:ok, netmaker_host_id} = Vpn.get_host_id(admin_name)
    Logger.info("Fetched Netmaker host ID: #{netmaker_host_id}")

    # Initial ETS state (placeholders - will be populated by first computation)
    :ets.insert(@table, {
      :admin,
      %{
        id: admin_id,
        name: admin_name,
        max_capacity: max_capacity,
        erlang_node_name: erlang_node_name,
        vpn_hostname: vpn_hostname,
        admin_cluster_name: admin_cluster_name,
        netmaker_host_id: netmaker_host_id,
        last_computed_at: nil
      }
    })

    :ets.insert(@table, {
      :admin_cluster,
      %{
        name: admin_cluster_name,
        total_admins: 0,
        total_nodes: 0,
        total_capacity: 0,
        degraded: false,
        topology: [],
        weak_leader: admin_name
      }
    })

    :ets.insert(@table, {
      :edge_clusters,
      %{admin_name => %{}}
    })

    :ets.insert(@table, {
      :orphaned_clusters,
      %{}
    })

    # Subscribe to PubSub events (cluster/node CRUD from this admin cluster)
    Phoenix.PubSub.subscribe(EdgeAdmin.PubSub, "#{admin_cluster_name}:metadata")

    # Initial state with flags
    initial_state = %{
      admin_id: admin_id,
      admin_cluster_name: admin_cluster_name,
      last_computed_at: nil,
      recomputing?: false,
      pending_recompute: false,
      initialized: false
    }

    # Trigger first recomputation
    spawn_recomputation_task(initial_state, :initialization)

    Logger.info("Metadata initialization complete for #{admin_name}")

    {:ok, %{initial_state | recomputing?: true, initialized: true}}
  end

  # === Public API (Queries) ===

  def get_admin do
    [{:admin, admin}] = :ets.lookup(@table, :admin)
    admin
  end

  def get_cluster_owner(cluster_name) do
    [{:edge_clusters, assignments}] = :ets.lookup(@table, :edge_clusters)

    Enum.find_value(assignments, fn {admin_name, clusters} ->
      if Map.has_key?(clusters, cluster_name), do: admin_name
    end)
  end

  @doc """
  Finds which cluster a node belongs to by searching ETS metadata.

  ## Parameters
  - node_name: Node name with "node-" prefix (e.g., "node-abc123")

  ## Returns
  - {:ok, cluster_name, admin_name} if found
  - {:error, :not_found} if node not assigned to any cluster
  """
  def find_node_cluster(node_name) do
    [{:edge_clusters, assignments}] = :ets.lookup(@table, :edge_clusters)

    result =
      Enum.find_value(assignments, fn {admin_name, clusters} ->
        Enum.find_value(clusters, fn {cluster_name, node_names} ->
          if node_name in node_names do
            {cluster_name, admin_name}
          end
        end)
      end)

    case result do
      {cluster_name, admin_name} -> {:ok, cluster_name, admin_name}
      nil -> {:error, :not_found}
    end
  end

  def get_my_clusters do
    [{:admin, %{name: admin_name}}] = :ets.lookup(@table, :admin)
    [{:edge_clusters, assignments}] = :ets.lookup(@table, :edge_clusters)
    Map.get(assignments, admin_name, %{})
  end

  def get_peer_admins do
    [{:admin_cluster, %{topology: topology}}] = :ets.lookup(@table, :admin_cluster)
    topology
  end

  def get_admin_cluster do
    [{:admin_cluster, admin_cluster}] = :ets.lookup(@table, :admin_cluster)
    admin_cluster
  end

  def get_edge_clusters do
    [{:edge_clusters, assignments}] = :ets.lookup(@table, :edge_clusters)
    assignments
  end

  def get_orphaned_clusters do
    [{:orphaned_clusters, orphaned}] = :ets.lookup(@table, :orphaned_clusters)
    orphaned
  end

  def degraded? do
    [{:admin_cluster, %{degraded: degraded}}] = :ets.lookup(@table, :admin_cluster)
    degraded
  end

  @doc """
  Returns true if this admin is the current weak leader of the admin cluster.

  The LocalScheduler runs certain jobs on every admin instance — by design, since
  there is no central coordinator. The weak leader is a best-effort optimisation
  to reduce duplicate work: all admins independently elect the same admin
  (alphabetically first admin ID in the current topology) and only that admin
  runs the job. Duplicate work is still possible and acceptable — during split
  brain, each partition elects its own weak leader independently.

  Do not use this for operations that require exactly-once guarantees. If strong
  leader semantics are ever needed, introduce a :strong_leader key separately.
  """
  def am_i_weak_leader? do
    [{:admin, %{name: my_name}}] = :ets.lookup(@table, :admin)
    [{:admin_cluster, %{weak_leader: weak_leader}}] = :ets.lookup(@table, :admin_cluster)
    my_name == weak_leader
  end

  def initialized? do
    case Process.whereis(__MODULE__) do
      nil ->
        false

      pid ->
        try do
          GenServer.call(pid, :initialized?, 1000)
        catch
          :exit, _ -> false
        end
    end
  end

  def recompute_now do
    GenServer.call(__MODULE__, {:recompute_now, :manual}, 10_000)
  end

  # === GenServer Callbacks ===

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  @impl true
  def handle_call({:recompute_now, trigger}, _from, state) do
    {:noreply, new_state} = request_recomputation(state, trigger)
    {:reply, :ok, new_state}
  end

  # === Event Handlers ===

  # Syn events - Admin topology changes (forwarded by SynEventHandler callback)
  @impl true
  def handle_info({:syn_admin_topology_changed, trigger}, state) do
    Logger.info("Metadata: admin topology changed (#{trigger}), requesting recomputation")
    request_recomputation(state, trigger)
  end

  # PostgreSQL events - Cluster structure changes
  @impl true
  def handle_info({:cluster_created, cluster_name}, state) do
    Logger.debug("Cluster created: #{cluster_name}, requesting recomputation")
    request_recomputation(state, :cluster_created)
  end

  @impl true
  def handle_info({:cluster_deleted, cluster_name}, state) do
    Logger.debug("Cluster deleted: #{cluster_name}, requesting recomputation")
    request_recomputation(state, :cluster_deleted)
  end

  # PostgreSQL events - Node changes
  @impl true
  def handle_info({:node_created, _node_id, _cluster_name}, state) do
    Logger.debug("Node created, requesting recomputation")
    request_recomputation(state, :node_created)
  end

  @impl true
  def handle_info({:node_deleted, _node_id, _cluster_name}, state) do
    Logger.debug("Node deleted, requesting recomputation")
    request_recomputation(state, :node_deleted)
  end

  @impl true
  def handle_info({:node_updated, _node_id, _old_cluster_name, _new_cluster_name}, state) do
    Logger.debug("Node updated, requesting recomputation")
    request_recomputation(state, :node_updated)
  end

  # Recomputation complete
  @impl true
  def handle_info({:recomputation_complete, trigger, duration}, state) do
    if state.pending_recompute do
      # Something changed while we worked - do it again
      Logger.debug("Metadata: Pending recomputation triggered")
      spawn_recomputation_task(state, :pending)
      {:noreply, %{state | recomputing?: true, pending_recompute: false}}
    else
      Logger.debug("Metadata: Recomputation complete, idle")

      # Emit recomputation telemetry
      emit_recomputation_telemetry(trigger, duration)

      {:noreply, %{state | recomputing?: false}}
    end
  end

  # === Private Helpers ===

  defp request_recomputation(state, trigger) do
    if state.recomputing? do
      # Already working - mark that we need to do it again
      Logger.debug("Metadata: Already recomputing, marked pending")
      {:noreply, %{state | pending_recompute: true}}
    else
      # Start recomputation
      spawn_recomputation_task(state, trigger)
      Logger.debug("Metadata: Starting recomputation")
      {:noreply, %{state | recomputing?: true}}
    end
  end

  defp spawn_recomputation_task(state, trigger) do
    parent = self()

    Task.start(fn ->
      start_time = System.monotonic_time(:millisecond)
      perform_recomputation(state)
      duration = System.monotonic_time(:millisecond) - start_time
      send(parent, {:recomputation_complete, trigger, duration})
    end)
  end

  defp perform_recomputation(_state) do
    Logger.debug("Performing metadata recomputation")

    # Read inputs from syn and PostgreSQL (already transformed to names)
    all_admins = read_admins_from_syn()
    clusters_with_names = read_clusters_from_db()

    # Run algorithm (works with any unique strings - IDs or names, doesn't matter)
    result = Algorithm.compute_assignments(all_admins, clusters_with_names)

    # Result already has names - ready for ETS!
    update_ets(result, all_admins)

    # Emit local event (only this admin's processes receive it)
    [{:admin, admin_info}] = :ets.lookup(@table, :admin)

    Phoenix.PubSub.local_broadcast(
      EdgeAdmin.PubSub,
      "#{admin_info.name}:metadata",
      :metadata_recomputed
    )

    Logger.debug("Metadata recomputation complete")

    :ok
  end

  defp read_admins_from_syn do
    # Get all admins from syn process group
    # :syn.members/2 returns list of {pid, metadata} tuples
    # Metadata contains: %{name: admin_name, max_capacity: capacity,
    #   erlang_node_name: ..., vpn_hostname: ..., netmaker_host_id: ...}
    [{:admin, admin_info}] = :ets.lookup(@table, :admin)
    admin_cluster_name = admin_info.admin_cluster_name

    try do
      members = :syn.members(:admin_scope, admin_cluster_name)
      Map.new(members, fn {_pid, metadata} -> {metadata.name, metadata} end)
    rescue
      ErlangError ->
        Logger.debug("Syn scope :admin_scope not initialized, returning empty admin list")
        %{}
    end
  end

  defp read_clusters_from_db do
    Nodes.list_cluster_node_mappings(prefix: true)
  end

  defp update_ets(result, all_admins) do
    # Update :edge_clusters
    :ets.insert(@table, {:edge_clusters, result.edge_clusters})

    # Update :orphaned_clusters
    :ets.insert(@table, {:orphaned_clusters, result.orphaned_clusters})

    # Update :admin_cluster topology
    [{:admin_cluster, admin_cluster}] = :ets.lookup(@table, :admin_cluster)

    # Extract metadata values
    topology = Map.values(all_admins)

    updated_admin_cluster = %{
      admin_cluster
      | topology: topology,
        total_admins: map_size(all_admins),
        total_nodes: result.total_nodes,
        total_capacity: result.total_capacity,
        degraded: result.degraded,
        weak_leader: result.weak_leader
    }

    :ets.insert(@table, {:admin_cluster, updated_admin_cluster})

    # Update :admin last_computed_at
    [{:admin, admin}] = :ets.lookup(@table, :admin)

    updated_admin = %{
      admin
      | last_computed_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    :ets.insert(@table, {:admin, updated_admin})

    :ok
  end

  defp emit_recomputation_telemetry(trigger, duration) do
    # Read current state from ETS
    [{:edge_clusters, edge_clusters}] = :ets.lookup(@table, :edge_clusters)
    [{:orphaned_clusters, orphaned_clusters}] = :ets.lookup(@table, :orphaned_clusters)
    [{:admin, admin}] = :ets.lookup(@table, :admin)
    [{:admin_cluster, admin_cluster}] = :ets.lookup(@table, :admin_cluster)

    # Count assigned clusters for this admin
    assigned_clusters =
      case Map.get(edge_clusters, admin.name) do
        nil -> 0
        clusters -> map_size(clusters)
      end

    orphaned_clusters_count = map_size(orphaned_clusters)
    degraded = if admin_cluster.degraded, do: 1, else: 0

    :telemetry.execute(
      [:edge_admin, :metadata, :recomputation],
      %{
        duration: duration,
        count: 1,
        assigned_clusters: assigned_clusters,
        orphaned_clusters: orphaned_clusters_count,
        degraded: degraded
      },
      %{trigger: trigger}
    )
  end
end
