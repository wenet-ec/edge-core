# edge_admin/lib/edge_admin/admins/metadata.ex
defmodule EdgeAdmin.Admins.Metadata do
  @moduledoc """
  Distributed metadata coordinator for admin cluster state and edge cluster assignments.

  This GenServer maintains a local, ephemeral ETS snapshot containing the current
  state of the admin cluster topology and cluster assignment decisions. Every Admin
  independently recomputes the same snapshot from the shared database and cluster
  events; ETS is not a replicated source of truth.

  ## Responsibilities

  1. **ETS Table Management**
     - Create and own `:metadata` ETS table
     - Provide public read API for queries
     - Replace the snapshot atomically during recomputations

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

  The `:metadata` table contains one `:snapshot` key. Its value is a map that
  contains the following fields. Replacing that one ETS entry means readers
  never combine values from different recomputations.

  ### `admin` - This Admin's Info
  ```elixir
  %{
    id: "abc123",
    name: "admin-abc123",
    max_wireguard_peers: 250,   # operator-configured WG peer budget
    admin_peer_count: 1,        # derived: total_admins - 1 (peers in admin mesh)
    edge_node_capacity: 249,    # derived: max_wireguard_peers - admin_peer_count
    erlang_node_name: :"admin@admin-abc123.admin-cluster-1.nm.internal",
    vpn_hostname: "admin-abc123.admin-cluster-1.nm.internal",
    admin_cluster_name: "admin-cluster-1",
    vpn_host_id: "95e2707e-...",
    last_computed_at: ~U[2025-01-15 12:00:00Z]
  }
  ```

  Invariant: `max_wireguard_peers == admin_peer_count + edge_node_capacity`.

  ### `admin_cluster` - Full Topology
  ```elixir
  %{
    name: "admin-cluster-1",
    total_admins: 2,
    total_nodes: 5,             # total nodes across all clusters in the system
    total_edge_capacity: 498,   # sum of edge_node_capacity across all admins
    degraded: false,            # true when total_nodes > total_edge_capacity
    weak_leader: "admin-abc123", # alphabetically first admin name; see am_i_weak_leader?/0
    topology: [
      %{name: "admin-abc123",
        max_wireguard_peers: 250, admin_peer_count: 1, edge_node_capacity: 249,
        vpn_hostname: ..., erlang_node_name: ..., vpn_host_id: "..."},
      %{name: "admin-def456",
        max_wireguard_peers: 350, admin_peer_count: 1, edge_node_capacity: 349, ...}
    ]
  }
  ```

  ### `edge_clusters` - Assignment Map
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

  ### `orphaned_clusters` - Unassigned Clusters
  ```elixir
  %{
    "cluster-orphaned-1" => ["node-5", "node-6"],
    "cluster-orphaned-2" => ["node-7"]
  }
  ```

  ### `node_index` - Inverted Node Index
  Rebuilt on every recomputation. O(1) lookup for `find_node_cluster/1`.
  ```elixir
  %{
    "node-abc123" => {"cluster-a", "admin-1"},
    "node-def456" => {"cluster-a", "admin-1"},
    "node-xyz789" => {"cluster-b", "admin-2"}
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

  ## Examples

      # Query metadata (from any process)
      iex> Metadata.get_my_clusters()
      %{"cluster-prod" => ["node-1", "node-2"], "cluster-dev" => []}

      # Trigger recomputation (from PubSub event)
      send(Metadata, :cluster_created)

      # Algorithm runs, assignments update, local subscribers are notified
  """

  use GenServer

  alias EdgeAdmin.Admins.Metadata.Algorithm
  alias EdgeAdmin.Admins.Metadata.Events
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Vpn

  require Logger

  @callback degraded?() :: boolean()

  @table :metadata
  @snapshot_key :snapshot

  @doc """
  Starts the Metadata GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    admin_id = Application.get_env(:edge_admin, :admin_id)
    admin_name = Application.get_env(:edge_admin, :admin_name)
    admin_cluster_name = Application.get_env(:edge_admin, :admin_cluster_name)
    max_wireguard_peers = Application.get_env(:edge_admin, :admin_max_wireguard_peers)

    Logger.info("Metadata initializing for admin #{admin_name}")

    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

    vpn_hostname = Vpn.build_vpn_hostname(admin_name, admin_cluster_name)
    erlang_node_name = node()

    {:ok, vpn_host_id} = Vpn.get_host_id(admin_name)
    Logger.info("Fetched VPN host ID: #{vpn_host_id}")

    # Initial ETS state (placeholders - will be populated by first computation).
    # admin_peer_count and edge_node_capacity reflect a lone admin (no peers yet);
    # they're recomputed on every metadata recomputation as topology changes.
    admin =
      %{
        id: admin_id,
        name: admin_name,
        max_wireguard_peers: max_wireguard_peers,
        admin_peer_count: 0,
        edge_node_capacity: max_wireguard_peers,
        erlang_node_name: erlang_node_name,
        vpn_hostname: vpn_hostname,
        admin_cluster_name: admin_cluster_name,
        vpn_host_id: vpn_host_id,
        last_computed_at: nil
      }

    admin_cluster =
      %{
        name: admin_cluster_name,
        total_admins: 0,
        total_nodes: 0,
        total_edge_capacity: 0,
        degraded: false,
        topology: [],
        weak_leader: admin_name
      }

    put_snapshot(%{
      admin: admin,
      admin_cluster: admin_cluster,
      edge_clusters: %{admin_name => %{}},
      orphaned_clusters: %{},
      node_index: %{}
    })

    Events.subscribe()

    initial_state = %{
      admin_id: admin_id,
      admin_cluster_name: admin_cluster_name,
      last_computed_at: nil,
      recomputing?: false,
      pending_recompute: false,
      last_recompute_error: nil,
      initialized: false
    }

    spawn_recomputation_task(initial_state, :initialization)

    Logger.info("Metadata initialization complete for #{admin_name}")

    {:ok, %{initial_state | recomputing?: true, initialized: true}}
  end

  @doc """
  Returns one internally consistent metadata snapshot.

  The snapshot is published as one ETS object after every recomputation, so a
  caller cannot observe a new topology together with old assignments.
  """
  @spec snapshot() :: map()
  def snapshot do
    [{@snapshot_key, snapshot}] = :ets.lookup(@table, @snapshot_key)
    snapshot
  end

  @doc "Returns this Admin's metadata from the current snapshot."
  @spec get_admin() :: map()
  def get_admin, do: snapshot().admin

  @doc "Returns the name of the Admin that currently owns the given edge cluster."
  @spec get_cluster_owner(String.t()) :: String.t() | nil
  def get_cluster_owner(cluster_name) do
    assignments = snapshot().edge_clusters

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
  @spec find_node_cluster(String.t()) ::
          {:ok, String.t(), String.t()} | {:error, :not_found}
  def find_node_cluster(node_name) do
    index = snapshot().node_index

    case Map.get(index, node_name) do
      {cluster_name, admin_name} -> {:ok, cluster_name, admin_name}
      nil -> {:error, :not_found}
    end
  end

  @doc "Returns the edge clusters currently assigned to this Admin."
  @spec get_my_clusters() :: %{optional(String.t()) => [String.t()]}
  def get_my_clusters do
    metadata = snapshot()
    Map.get(metadata.edge_clusters, metadata.admin.name, %{})
  end

  @doc "Returns the current admin topology entries for this admin cluster."
  @spec get_peer_admins() :: [map()]
  def get_peer_admins do
    snapshot().admin_cluster.topology
  end

  @doc "Returns the current admin-cluster topology and capacity snapshot."
  @spec get_admin_cluster() :: map()
  def get_admin_cluster do
    snapshot().admin_cluster
  end

  @doc "Returns the complete edge-cluster-to-admin assignment map."
  @spec get_edge_clusters() :: %{optional(String.t()) => map()}
  def get_edge_clusters do
    snapshot().edge_clusters
  end

  @doc "Returns edge clusters that currently have no assigned Admin."
  @spec get_orphaned_clusters() :: %{optional(String.t()) => [String.t()]}
  def get_orphaned_clusters do
    snapshot().orphaned_clusters
  end

  @doc "Returns whether the admin cluster currently exceeds its edge capacity."
  @spec degraded?() :: boolean()
  def degraded? do
    snapshot().admin_cluster.degraded
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
  @spec am_i_weak_leader?() :: boolean()
  def am_i_weak_leader? do
    metadata = snapshot()
    metadata.admin.name == metadata.admin_cluster.weak_leader
  end

  @doc """
  Returns the current recomputation lifecycle state for operator-facing views.
  """
  @spec status() :: map()
  def status do
    case Process.whereis(__MODULE__) do
      nil ->
        %{recomputing?: false, pending_recompute: false, last_recompute_error: nil}

      pid ->
        try do
          GenServer.call(pid, :status, 1_000)
        catch
          :exit, _ -> %{recomputing?: false, pending_recompute: false, last_recompute_error: nil}
        end
    end
  end

  @doc "Returns whether the Metadata GenServer has completed initial setup."
  @spec initialized?() :: boolean()
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

  @doc "Requests an asynchronous metadata recomputation and returns immediately after it is queued."
  @spec recompute_now() :: :ok
  def recompute_now do
    GenServer.call(__MODULE__, {:recompute_now, :manual}, 10_000)
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  def handle_call(:status, _from, state) do
    {:reply, Map.take(state, [:recomputing?, :pending_recompute, :last_recompute_error]), state}
  end

  @impl true
  def handle_call({:recompute_now, trigger}, _from, state) do
    {:noreply, new_state} = request_recomputation(state, trigger)
    {:reply, :ok, new_state}
  end

  # Admin topology changes forwarded by SynEventHandler.
  @impl true
  def handle_info({:syn_admin_topology_changed, trigger}, state) do
    Logger.info("Metadata: admin topology changed (#{trigger}), requesting recomputation")
    request_recomputation(state, trigger)
  end

  @impl true
  def handle_info(:cluster_created, state) do
    Logger.debug("Cluster created, requesting recomputation")
    request_recomputation(state, :cluster_created)
  end

  @impl true
  def handle_info(:cluster_deleted, state) do
    Logger.debug("Cluster deleted, requesting recomputation")
    request_recomputation(state, :cluster_deleted)
  end

  @impl true
  def handle_info(:node_created, state) do
    Logger.debug("Node created, requesting recomputation")
    request_recomputation(state, :node_created)
  end

  @impl true
  def handle_info(:node_deleted, state) do
    Logger.debug("Node deleted, requesting recomputation")
    request_recomputation(state, :node_deleted)
  end

  @impl true
  def handle_info(:node_updated, state) do
    Logger.debug("Node updated, requesting recomputation")
    request_recomputation(state, :node_updated)
  end

  @impl true
  def handle_info({:recomputation_finished, trigger, duration, :ok}, state) do
    if state.pending_recompute do
      Logger.debug("Metadata: Pending recomputation triggered")
      spawn_recomputation_task(state, :pending)
      {:noreply, %{state | recomputing?: true, pending_recompute: false, last_recompute_error: nil}}
    else
      Logger.debug("Metadata: Recomputation complete, idle")

      emit_recomputation_telemetry(trigger, duration)

      {:noreply, %{state | recomputing?: false, last_recompute_error: nil}}
    end
  end

  def handle_info({:recomputation_finished, trigger, _duration, {:error, reason}}, state) do
    Logger.error("Metadata recomputation failed (#{trigger}): #{reason}")

    if state.pending_recompute do
      spawn_recomputation_task(state, :pending)

      {:noreply,
       %{
         state
         | recomputing?: true,
           pending_recompute: false,
           last_recompute_error: reason
       }}
    else
      {:noreply, %{state | recomputing?: false, last_recompute_error: reason}}
    end
  end

  defp request_recomputation(state, trigger) do
    if state.recomputing? do
      Logger.debug("Metadata: Already recomputing, marked pending")
      {:noreply, %{state | pending_recompute: true}}
    else
      spawn_recomputation_task(state, trigger)
      Logger.debug("Metadata: Starting recomputation")
      {:noreply, %{state | recomputing?: true}}
    end
  end

  defp spawn_recomputation_task(state, trigger) do
    parent = self()

    Task.start(fn ->
      start_time = System.monotonic_time(:millisecond)

      result =
        try do
          perform_recomputation(state)
          :ok
        rescue
          exception -> {:error, Exception.message(exception)}
        catch
          kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
        end

      duration = System.monotonic_time(:millisecond) - start_time
      send(parent, {:recomputation_finished, trigger, duration, result})
    end)
  end

  defp perform_recomputation(_state) do
    Logger.debug("Performing metadata recomputation")

    all_admins = read_admins_from_syn()
    clusters_with_names = read_clusters_from_db()

    # Derive edge_node_capacity per admin from max_wireguard_peers and topology size.
    # admin_peer_count = total_admins - 1 (peers in admin mesh, excluding self).
    # edge_node_capacity = max_wireguard_peers - admin_peer_count.
    # This is what the algorithm consumes — admins enriched with all three numbers.
    enriched_admins = derive_capacity(all_admins)

    # Run from shared inputs only so every admin in the cluster converges on the
    # same owner map.
    result = Algorithm.compute_assignments(enriched_admins, clusters_with_names)

    update_ets(result, enriched_admins)

    Events.publish_local(:metadata_recomputed)

    Logger.debug("Metadata recomputation complete")

    :ok
  end

  defp read_admins_from_syn do
    # :syn.members/2 returns list of {pid, metadata} tuples
    # Metadata contains: %{name: admin_name, max_wireguard_peers: int,
    #   erlang_node_name: ..., vpn_hostname: ..., vpn_host_id: ...}
    admin_cluster_name = snapshot().admin.admin_cluster_name

    try do
      members = :syn.members(:admin_scope, admin_cluster_name)
      Map.new(members, fn {_pid, metadata} -> {metadata.name, metadata} end)
    rescue
      ErlangError ->
        Logger.debug("Syn scope :admin_scope not initialized, returning empty admin list")
        %{}
    end
  end

  # Enrich syn-sourced admin metadata with derived capacity numbers.
  # admin_peer_count is the same for every admin in a given recompute (total_admins - 1),
  # but each admin's max_wireguard_peers is its own — and so its edge_node_capacity is too.
  defp derive_capacity(all_admins) do
    admin_peer_count = max(map_size(all_admins) - 1, 0)

    Map.new(all_admins, fn {name, metadata} ->
      max_wg = metadata.max_wireguard_peers

      enriched =
        Map.merge(metadata, %{
          admin_peer_count: admin_peer_count,
          edge_node_capacity: max_wg - admin_peer_count
        })

      {name, enriched}
    end)
  end

  defp read_clusters_from_db do
    Nodes.list_cluster_node_mappings(prefix: true)
  end

  defp update_ets(result, all_admins) do
    previous = snapshot()
    admin_cluster = previous.admin_cluster

    topology = Map.values(all_admins)

    updated_admin_cluster = %{
      admin_cluster
      | topology: topology,
        total_admins: map_size(all_admins),
        total_nodes: result.total_nodes,
        total_edge_capacity: result.total_edge_capacity,
        degraded: result.degraded,
        weak_leader: result.weak_leader
    }

    # Update :admin last_computed_at and the derived capacity fields for self.
    admin = previous.admin
    self_enriched = Map.fetch!(all_admins, admin.name)

    updated_admin = %{
      admin
      | admin_peer_count: self_enriched.admin_peer_count,
        edge_node_capacity: self_enriched.edge_node_capacity,
        last_computed_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    put_snapshot(%{
      admin: updated_admin,
      admin_cluster: updated_admin_cluster,
      edge_clusters: result.edge_clusters,
      orphaned_clusters: result.orphaned_clusters,
      node_index: result.node_index
    })

    :ok
  end

  defp emit_recomputation_telemetry(trigger, duration) do
    metadata = snapshot()
    edge_clusters = metadata.edge_clusters
    orphaned_clusters = metadata.orphaned_clusters
    admin = metadata.admin
    admin_cluster = metadata.admin_cluster

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

  defp put_snapshot(snapshot) do
    :ets.insert(@table, {@snapshot_key, snapshot})
  end
end
