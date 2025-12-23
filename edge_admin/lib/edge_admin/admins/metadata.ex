# edge_admin/lib/edge_admin/admins/metadata.ex
defmodule EdgeAdmin.Admins.Metadata do
  @moduledoc """
  Core coordination GenServer for admin cluster metadata.

  Responsibilities:
  - ETS table ownership and lifecycle management
  - Event subscription (syn for admin topology, Phoenix PubSub for PostgreSQL changes)
  - Recompute state machine logic (pending flag pattern)
  - Recomputation orchestration (triggers Algorithm module)
  - ETS updates (write assignments, topology, system state)
  - Public API for ETS queries
  ## ETS Schema

  The `:metadata` table contains 4 keys:

  ```elixir
  :admin => %{
    id: "abc123",
    name: "admin-abc123",
    max_capacity: 200,
    erlang_node_name: :"admin@admin-abc123.admin-cluster-1.nm.internal",
    dns_hostname: "admin-abc123.admin-cluster-1.nm.internal",
    admin_cluster_name: "admin-cluster-1",
    netmaker_host_id: "95e2707e-d11f-4551-bdd4-4ab2ab917505",
    last_computed_at: ~U[2025-01-15 12:00:00Z]
  }

  :admin_cluster => %{
    name: "admin-cluster-1",
    total_admins: 2,
    degraded: false,
    topology: [
      %{name: "admin-abc123", max_capacity: 200, dns_hostname: ..., erlang_node_name: ..., netmaker_host_id: "..."},
      %{name: "admin-def456", max_capacity: 300, dns_hostname: ..., erlang_node_name: ..., netmaker_host_id: "..."}
    ]
  }

  :edge_clusters => %{
    "admin-abc123" => %{
      "cluster-a" => ["node-1", "node-2"],
      "cluster-b" => []
    },
    "admin-def456" => %{
      "cluster-c" => ["node-3"]
    }
  }

  :orphaned_clusters => %{
    "cluster-orphaned-1" => ["node-5", "node-6"],
    "cluster-orphaned-2" => ["node-7"]
  }

  Note: edge_clusters uses admin_name (e.g., "admin-abc123") as keys, not admin_id.
  ```
  """

  use GenServer

  require Logger

  alias EdgeAdmin.Admins.Metadata.Algorithm
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Vpn

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
    dns_hostname = Vpn.build_hostname(admin_name, admin_cluster_name)
    erlang_node_name = Node.self()

    # Fetch Netmaker host ID
    {:ok, netmaker_host_id} = EdgeAdmin.Vpn.get_host_id(admin_name)
    Logger.info("Fetched Netmaker host ID: #{netmaker_host_id}")

    # Initial ETS state (placeholders - will be populated by first computation)
    :ets.insert(@table, {
      :admin,
      %{
        id: admin_id,
        name: admin_name,
        max_capacity: max_capacity,
        erlang_node_name: erlang_node_name,
        dns_hostname: dns_hostname,
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
        degraded: false,
        topology: []
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
    spawn_recomputation_task(initial_state)

    Logger.info("Metadata initialization complete for #{admin_name}")

    {:ok, %{initial_state | recomputing?: true, initialized: true}}
  end

  # === Public API (Queries) ===

  def get_admin do
    [{:admin, admin}] = :ets.lookup(@table, :admin)
    admin
  end

  def get_cluster_owner(cluster_id) do
    [{:edge_clusters, assignments}] = :ets.lookup(@table, :edge_clusters)

    Enum.find_value(assignments, fn {admin_name, clusters} ->
      if Map.has_key?(clusters, cluster_id), do: admin_name
    end)
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
    GenServer.call(__MODULE__, :recompute_now, 10_000)
  end

  # === GenServer Callbacks ===

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  @impl true
  def handle_call(:recompute_now, _from, state) do
    if state.recomputing? do
      # Already working - mark pending
      {:reply, :ok, %{state | pending_recompute: true}}
    else
      # Start recomputation
      spawn_recomputation_task(state)
      {:reply, :ok, %{state | recomputing?: true}}
    end
  end

  # === Event Handlers ===

  # Syn events (admin topology changes)
  @impl true
  def handle_info({:syn_event, :admin_scope, {:join, admin_id, _pid, _metadata}}, state) do
    Logger.info("Admin joined: #{admin_id}, requesting recomputation")
    request_recomputation(state)
  end

  @impl true
  def handle_info({:syn_event, :admin_scope, {:leave, admin_id, _pid, _metadata}}, state) do
    Logger.info("Admin left: #{admin_id}, requesting recomputation")
    request_recomputation(state)
  end

  # PostgreSQL events - Cluster structure changes
  @impl true
  def handle_info({:cluster_created, cluster_id}, state) do
    Logger.debug("Cluster created: #{cluster_id}, requesting recomputation")
    request_recomputation(state)
  end

  @impl true
  def handle_info({:cluster_deleted, cluster_id}, state) do
    Logger.debug("Cluster deleted: #{cluster_id}, requesting recomputation")
    request_recomputation(state)
  end

  # PostgreSQL events - Node changes
  @impl true
  def handle_info({:node_created, _node_id, _cluster_id}, state) do
    Logger.debug("Node created, requesting recomputation")
    request_recomputation(state)
  end

  @impl true
  def handle_info({:node_deleted, _node_id, _cluster_id}, state) do
    Logger.debug("Node deleted, requesting recomputation")
    request_recomputation(state)
  end

  @impl true
  def handle_info({:node_updated, _node_id, _old_cluster_id, _new_cluster_id}, state) do
    Logger.debug("Node updated, requesting recomputation")
    request_recomputation(state)
  end

  # Recomputation complete
  @impl true
  def handle_info(:recomputation_complete, state) do
    if state.pending_recompute do
      # Something changed while we worked - do it again
      Logger.debug("Metadata: Pending recomputation triggered")
      spawn_recomputation_task(state)
      {:noreply, %{state | recomputing?: true, pending_recompute: false}}
    else
      Logger.debug("Metadata: Recomputation complete, idle")
      {:noreply, %{state | recomputing?: false}}
    end
  end

  # === Private Helpers ===

  defp request_recomputation(state) do
    if state.recomputing? do
      # Already working - mark that we need to do it again
      Logger.debug("Metadata: Already recomputing, marked pending")
      {:noreply, %{state | pending_recompute: true}}
    else
      # Start recomputation
      spawn_recomputation_task(state)
      Logger.debug("Metadata: Starting recomputation")
      {:noreply, %{state | recomputing?: true}}
    end
  end

  defp spawn_recomputation_task(state) do
    parent = self()

    Task.start(fn ->
      perform_recomputation(state)
      send(parent, :recomputation_complete)
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
    # Metadata contains: %{name: admin_name, max_capacity: capacity, erlang_node_name: ..., dns_hostname: ..., netmaker_host_id: ...}
    [{:admin, admin_info}] = :ets.lookup(@table, :admin)
    admin_cluster_name = admin_info.admin_cluster_name

    try do
      case :syn.members(:admin_scope, admin_cluster_name) do
        members when is_list(members) ->
          members
          |> Enum.map(fn {_pid, metadata} -> {metadata.name, metadata} end)
          |> Map.new()

        _ ->
          %{}
      end
    rescue
      ErlangError ->
        Logger.debug("Syn scope :admin_scope not initialized, returning empty admin list")
        %{}
    end
  end

  defp read_clusters_from_db do
    Nodes.list_cluster_node_mappings()
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

    # Use degraded flag from algorithm result
    updated_admin_cluster = %{
      admin_cluster
      | topology: topology,
        total_admins: map_size(all_admins),
        degraded: result.degraded
    }

    :ets.insert(@table, {:admin_cluster, updated_admin_cluster})

    # Update :admin last_computed_at
    [{:admin, admin}] = :ets.lookup(@table, :admin)

    updated_admin = %{
      admin
      | last_computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    :ets.insert(@table, {:admin, updated_admin})

    :ok
  end
end
