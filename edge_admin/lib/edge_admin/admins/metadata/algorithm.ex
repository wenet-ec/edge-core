# edge_admin/lib/edge_admin/admins/metadata/algorithm.ex
defmodule EdgeAdmin.Admins.Metadata.Algorithm do
  @moduledoc """
  Pure algorithm for one-admin-per-cluster assignments.

  Core features:
  - Deterministic consensus (same inputs → same outputs)
  - Degraded mode support (tracks unassigned nodes when capacity exceeded)
  - Empty cluster bootstrap (pre-assignment before first node joins)
  - Smart load balancing (prefers admins with fewer clusters, then higher remaining capacity)
  """

  @doc """
  Computes cluster assignments from scratch.

  ## Arguments
  - admins: %{admin_name => %{max_capacity: int}}
  - clusters: [%{name: cluster_name, nodes: [node_name, ...]}]

  ## Returns (ETS format - ready for direct insertion)
  %{
    edge_clusters: %{admin_name => %{cluster_name => [node_names]}},
    orphaned_clusters: %{cluster_name => [node_names]},
    degraded: boolean  # true if any cluster couldn't be assigned
  }

  ## Example
      iex> admins = %{
      ...>   "admin-1" => %{max_capacity: 200},
      ...>   "admin-2" => %{max_capacity: 300}
      ...> }
      iex> clusters = [
      ...>   %{name: "cluster-a", nodes: ["node-1", "node-2", "node-3"]},
      ...>   %{name: "cluster-b", nodes: ["node-4", "node-5"]}
      ...> ]
      iex> EdgeAdmin.Admins.Metadata.Algorithm.compute_assignments(admins, clusters)
      %{
        edge_clusters: %{
          "admin-1" => %{"cluster-b" => ["node-4", "node-5"]},
          "admin-2" => %{"cluster-a" => ["node-1", "node-2", "node-3"]}
        },
        orphaned_clusters: %{},
        degraded: false
      }
  """
  def compute_assignments(admins, clusters) do
    # Build cluster lookup map (cluster_name => nodes)
    cluster_nodes_map = Map.new(clusters, fn cluster -> {cluster.name, cluster.nodes} end)

    # Start with empty assignments
    initial_state = %{
      cluster_assignments: %{},
      admin_node_counts: Map.new(admins, fn {admin_name, _} -> {admin_name, 0} end),
      orphaned_clusters: %{}
    }

    # Assign each cluster
    intermediate_result =
      Enum.reduce(clusters, initial_state, fn cluster, state ->
        cluster_size = length(cluster.nodes)

        case find_best_admin_for_cluster(
               admins,
               state.cluster_assignments,
               state.admin_node_counts,
               cluster_size
             ) do
          {:ok, best_admin} ->
            # Assign cluster to admin
            %{
              cluster_assignments: Map.put(state.cluster_assignments, cluster.name, best_admin),
              admin_node_counts: Map.update!(state.admin_node_counts, best_admin, &(&1 + cluster_size)),
              orphaned_clusters: state.orphaned_clusters
            }

          {:error, :no_capacity} ->
            # Cluster couldn't be assigned - add to orphaned clusters
            %{
              state
              | orphaned_clusters: Map.put(state.orphaned_clusters, cluster.name, cluster.nodes)
            }
        end
      end)

    # Transform to ETS format: %{admin_name => %{cluster_name => [node_names]}}
    edge_clusters =
      build_edge_clusters_map(
        intermediate_result.cluster_assignments,
        cluster_nodes_map,
        admins
      )

    %{
      edge_clusters: edge_clusters,
      orphaned_clusters: intermediate_result.orphaned_clusters,
      degraded: map_size(intermediate_result.orphaned_clusters) > 0
    }
  end

  @doc """
  Bootstrap empty cluster by pre-assigning to best available admin.

  Called by REST API when user creates new cluster, before any nodes join.

  ## Arguments
  - admins: %{admin_name => %{max_capacity: int}}
  - current_assignments: result from compute_assignments/2 (has edge_clusters)
  - cluster_name: cluster to bootstrap

  ## Returns
  {:ok, admin_name} | {:error, :no_capacity}

  ## Example
      iex> admins = %{"admin-1" => %{max_capacity: 200}}
      iex> current = %{edge_clusters: %{"admin-1" => %{}}}
      iex> EdgeAdmin.Admins.Metadata.Algorithm.bootstrap_empty_cluster(admins, current, "cluster-new")
      {:ok, "admin-1"}
  """
  def bootstrap_empty_cluster(admins, current_assignments, cluster_name) do
    # Check if already assigned (search in edge_clusters)
    existing_owner =
      Enum.find_value(current_assignments.edge_clusters, fn {admin_name, clusters} ->
        if Map.has_key?(clusters, cluster_name), do: admin_name
      end)

    case existing_owner do
      nil ->
        # Extract cluster_assignments from edge_clusters for algorithm
        cluster_assignments = extract_cluster_assignments(current_assignments.edge_clusters)
        admin_node_counts = calculate_admin_node_counts(current_assignments.edge_clusters)

        # Find best admin for empty cluster (size = 0)
        find_best_admin_for_cluster(
          admins,
          cluster_assignments,
          admin_node_counts,
          # empty cluster
          0
        )

      admin_name ->
        {:ok, admin_name}
    end
  end

  # Private helpers

  defp find_best_admin_for_cluster(admins, cluster_assignments, admin_node_counts, cluster_size) do
    # Filter admins that can handle this cluster
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
        # Score each admin: prefer fewer clusters managed, then higher remaining capacity
        best_admin =
          Enum.min_by(admins_list, fn admin_name ->
            admin_score(admin_name, admins, cluster_assignments, admin_node_counts)
          end)

        {:ok, best_admin}
    end
  end

  defp can_admin_handle_cluster?(admin, current_node_count, additional_cluster_size) do
    current_node_count + additional_cluster_size <= admin.max_capacity
  end

  defp admin_score(admin_name, admins, cluster_assignments, admin_node_counts) do
    # How many clusters is this admin currently managing?
    clusters_managed =
      Enum.count(cluster_assignments, fn {_cluster_name, assigned_admin} -> assigned_admin == admin_name end)

    # How much remaining capacity does this admin have?
    remaining_capacity = admins[admin_name].max_capacity - admin_node_counts[admin_name]

    # Return tuple: (clusters_managed, -remaining_capacity)
    # Lower is better: prefer fewer clusters, then higher remaining capacity
    {clusters_managed, -remaining_capacity}
  end

  defp build_edge_clusters_map(cluster_assignments, cluster_nodes_map, admins) do
    # Initialize all admins with empty maps
    initial_map = Map.new(admins, fn {admin_name, _} -> {admin_name, %{}} end)

    # Group clusters by admin
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
    # Flatten edge_clusters back to %{cluster_name => admin_name}
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
    # Count total nodes per admin
    Map.new(edge_clusters, fn {admin_name, clusters} ->
      node_count = clusters |> Map.values() |> Enum.flat_map(& &1) |> length()
      {admin_name, node_count}
    end)
  end
end
