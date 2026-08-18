# edge_admin/lib/edge_admin/admin_clustering/metadata/algorithm.ex
defmodule EdgeAdmin.AdminClustering.Metadata.Algorithm do
  @moduledoc """
  Pure algorithm for one-admin-per-cluster assignments.

  The algorithm is deterministic: the same admins and clusters produce the same
  owner map on every admin instance. It recomputes assignments from scratch,
  tracks unassigned clusters when capacity is exceeded, and uses stable hash
  affinity only as a final load-balancing tiebreaker.

  ## Capacity model

  The algorithm operates on `edge_node_capacity` per admin — the number of edge nodes
  this admin can own. This is a derived value. Operators configure
  `max_wireguard_peers` (the WireGuard peer budget for this admin), and the metadata
  layer subtracts admin-mesh peers (`total_admins - 1`) to produce `edge_node_capacity`.
  The algorithm itself doesn't know about WG peers — it just sees the edge budget.
  """

  @doc """
  Computes cluster assignments from scratch on every call — no incremental updates, no shedding.

  Clusters are sorted by size descending, then cluster name ascending, so large
  clusters get first pick of admins and equal-sized clusters still have stable order.
  Each cluster is assigned to the best available admin scored by:
    1. Fewest clusters currently managed (prefer less-loaded admins)
    2. Highest remaining capacity (tiebreaker)
    3. Stable hash affinity for `{cluster_name, admin_name}` (tiebreaker)
    4. Admin ID alphabetically (deterministic final tiebreaker, consistent with weak-leader election)

  Hash affinity only kicks in when a cluster has multiple admins tied on (1) and
  (2). It is intentionally stateless: all admins compute the same affinity from
  shared inputs, so placement converges across the admin cluster.

  Clusters that cannot fit any admin (total capacity exceeded) are placed in `orphaned_clusters`.

  ## Arguments
  - admins: %{admin_name => %{edge_node_capacity: int}}
  - clusters: [%{name: cluster_name, nodes: [node_name, ...]}]

  ## Returns (ETS format - ready for direct insertion)
  %{
    edge_clusters: %{admin_name => %{cluster_name => [node_names]}},
    orphaned_clusters: %{cluster_name => [node_names]},
    node_index: %{node_name => {cluster_name, admin_name}},  # inverted index for O(1) node lookups
    total_nodes: integer,           # total nodes across all clusters in the system
    total_edge_capacity: integer,   # sum of edge_node_capacity across all admins
    degraded: boolean,              # true when total_nodes > total_edge_capacity
    weak_leader: admin_name         # alphabetically first admin ID — used to reduce duplicate LocalScheduler work
  }

  ## Example
      iex> admins = %{
      ...>   "admin-1" => %{edge_node_capacity: 199},
      ...>   "admin-2" => %{edge_node_capacity: 299}
      ...> }
      iex> clusters = [
      ...>   %{name: "cluster-a", nodes: ["node-1", "node-2", "node-3"]},
      ...>   %{name: "cluster-b", nodes: ["node-4", "node-5"]}
      ...> ]
      iex> EdgeAdmin.AdminClustering.Metadata.Algorithm.compute_assignments(admins, clusters)
      %{
        edge_clusters: %{
          "admin-1" => %{"cluster-b" => ["node-4", "node-5"]},
          "admin-2" => %{"cluster-a" => ["node-1", "node-2", "node-3"]}
        },
        node_index: %{
          "node-1" => {"cluster-a", "admin-2"},
          "node-2" => {"cluster-a", "admin-2"},
          "node-3" => {"cluster-a", "admin-2"},
          "node-4" => {"cluster-b", "admin-1"},
          "node-5" => {"cluster-b", "admin-1"}
        },
        orphaned_clusters: %{},
        total_nodes: 5,
        total_edge_capacity: 498,
        degraded: false,
        weak_leader: "admin-1"
      }
  """
  def compute_assignments(admins, clusters) do
    cluster_nodes_map = Map.new(clusters, fn cluster -> {cluster.name, cluster.nodes} end)

    total_nodes = Enum.reduce(clusters, 0, fn cluster, acc -> acc + length(cluster.nodes) end)

    total_edge_capacity = Enum.reduce(admins, 0, fn {_name, admin}, acc -> acc + admin.edge_node_capacity end)

    initial_state = %{
      cluster_assignments: %{},
      admin_node_counts: Map.new(admins, fn {admin_name, _} -> {admin_name, 0} end),
      orphaned_clusters: %{}
    }

    # Sort clusters by size descending, then name ascending: large clusters get
    # first pick of admins, and equal-sized clusters still have a stable order
    # across admins even if PostgreSQL returns rows differently.
    # This makes assignments stable (a small cluster can't steal the best admin from a
    # large one) and ensures deterministic output regardless of DB/map iteration order.
    sorted_clusters = Enum.sort_by(clusters, fn c -> {-length(c.nodes), c.name} end)

    intermediate_result =
      Enum.reduce(sorted_clusters, initial_state, fn cluster, state ->
        cluster_size = length(cluster.nodes)

        case find_best_admin_for_cluster(
               admins,
               state.cluster_assignments,
               state.admin_node_counts,
               cluster_size,
               cluster.name
             ) do
          {:ok, best_admin} ->
            %{
              cluster_assignments: Map.put(state.cluster_assignments, cluster.name, best_admin),
              admin_node_counts: Map.update!(state.admin_node_counts, best_admin, &(&1 + cluster_size)),
              orphaned_clusters: state.orphaned_clusters
            }

          {:error, :no_capacity} ->
            %{
              state
              | orphaned_clusters: Map.put(state.orphaned_clusters, cluster.name, cluster.nodes)
            }
        end
      end)

    edge_clusters =
      build_edge_clusters_map(
        intermediate_result.cluster_assignments,
        cluster_nodes_map,
        admins
      )

    weak_leader =
      admins
      |> Map.keys()
      |> Enum.min(fn -> nil end)

    %{
      edge_clusters: edge_clusters,
      node_index: build_node_index(edge_clusters),
      orphaned_clusters: intermediate_result.orphaned_clusters,
      total_nodes: total_nodes,
      total_edge_capacity: total_edge_capacity,
      degraded: total_nodes > total_edge_capacity,
      weak_leader: weak_leader
    }
  end

  @doc """
  Bootstrap empty cluster by pre-assigning to best available admin.

  Called by REST API when user creates new cluster, before any nodes join.

  ## Arguments
  - admins: %{admin_name => %{edge_node_capacity: int}}
  - current_assignments: result from compute_assignments/2 (has edge_clusters)
  - cluster_name: cluster to bootstrap

  ## Returns
  {:ok, admin_name} | {:error, :no_capacity}

  ## Example
      iex> admins = %{"admin-1" => %{edge_node_capacity: 199}}
      iex> current = %{edge_clusters: %{"admin-1" => %{}}}
      iex> EdgeAdmin.AdminClustering.Metadata.Algorithm.bootstrap_empty_cluster(admins, current, "cluster-new")
      {:ok, "admin-1"}
  """
  def bootstrap_empty_cluster(admins, current_assignments, cluster_name) do
    existing_owner =
      Enum.find_value(current_assignments.edge_clusters, fn {admin_name, clusters} ->
        if Map.has_key?(clusters, cluster_name), do: admin_name
      end)

    case existing_owner do
      nil ->
        cluster_assignments = extract_cluster_assignments(current_assignments.edge_clusters)
        admin_node_counts = calculate_admin_node_counts(current_assignments.edge_clusters)

        # Find best admin for empty cluster (size = 0).
        find_best_admin_for_cluster(admins, cluster_assignments, admin_node_counts, 0, cluster_name)

      admin_name ->
        {:ok, admin_name}
    end
  end

  defp find_best_admin_for_cluster(admins, cluster_assignments, admin_node_counts, cluster_size, cluster_name) do
    available_admins =
      admins
      |> Enum.filter(fn {admin_name, admin} ->
        can_admin_handle_cluster?(admin, admin_node_counts[admin_name], cluster_size)
      end)
      |> Enum.map(fn {admin_name, _} -> admin_name end)

    case available_admins do
      [] ->
        {:error, :no_capacity}

      admins_list ->
        # Score each admin: prefer fewer clusters managed, then higher remaining capacity,
        # then stable per-cluster hash affinity, then admin_name as final tiebreaker.
        best_admin =
          Enum.min_by(admins_list, fn admin_name ->
            {s1, s2} = admin_score(admin_name, admins, cluster_assignments, admin_node_counts)
            affinity = hash_affinity_score(cluster_name, admin_name)
            {s1, s2, affinity, admin_name}
          end)

        {:ok, best_admin}
    end
  end

  defp can_admin_handle_cluster?(admin, current_node_count, additional_cluster_size) do
    current_node_count + additional_cluster_size <= admin.edge_node_capacity
  end

  defp admin_score(admin_name, admins, cluster_assignments, admin_node_counts) do
    clusters_managed =
      Enum.count(cluster_assignments, fn {_cluster_name, assigned_admin} -> assigned_admin == admin_name end)

    remaining_capacity = admins[admin_name].edge_node_capacity - admin_node_counts[admin_name]

    {clusters_managed, -remaining_capacity}
  end

  defp hash_affinity_score(cluster_name, admin_name) do
    :sha256
    |> :crypto.hash([cluster_name, <<0>>, admin_name])
    |> :binary.decode_unsigned()
  end

  defp build_node_index(edge_clusters) do
    edge_clusters
    |> Enum.flat_map(fn {admin_name, clusters} ->
      Enum.flat_map(clusters, fn {cluster_name, nodes} ->
        Enum.map(nodes, fn node -> {node, {cluster_name, admin_name}} end)
      end)
    end)
    |> Map.new()
  end

  defp build_edge_clusters_map(cluster_assignments, cluster_nodes_map, admins) do
    initial_map = Map.new(admins, fn {admin_name, _} -> {admin_name, %{}} end)

    Enum.reduce(cluster_assignments, initial_map, fn {cluster_name, admin_name}, acc ->
      cluster_nodes = Map.get(cluster_nodes_map, cluster_name, [])

      Map.update!(acc, admin_name, fn admin_clusters ->
        Map.put(admin_clusters, cluster_name, cluster_nodes)
      end)
    end)
  end

  @doc """
  Extract flat cluster assignments from edge_clusters format.
  Returns %{cluster_name => admin_name}

  Used internally and for testing.
  """
  def extract_cluster_assignments(edge_clusters) do
    edge_clusters
    |> Enum.flat_map(fn {admin_name, clusters} ->
      Enum.map(clusters, fn {cluster_name, _nodes} -> {cluster_name, admin_name} end)
    end)
    |> Map.new()
  end

  @doc """
  Calculate admin node counts from edge_clusters format.
  Returns %{admin_name => node_count}

  Used internally and for testing.
  """
  def calculate_admin_node_counts(edge_clusters) do
    Map.new(edge_clusters, fn {admin_name, clusters} ->
      node_count = clusters |> Map.values() |> Enum.flat_map(& &1) |> length()
      {admin_name, node_count}
    end)
  end
end
