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
  - admins: %{admin_id => %{max_capacity: int}}
  - clusters: [%{id: cluster_id, nodes: [node_id, ...]}]

  ## Returns (ETS format - ready for direct insertion)
  %{
    edge_clusters: %{admin_id => %{cluster_id => [node_ids]}},
    success: boolean  # false if any cluster couldn't be assigned
  }

  ## Example
      iex> admins = %{
      ...>   "admin-1" => %{max_capacity: 200},
      ...>   "admin-2" => %{max_capacity: 300}
      ...> }
      iex> clusters = [
      ...>   %{id: "cluster-a", nodes: ["node-1", "node-2", "node-3"]},
      ...>   %{id: "cluster-b", nodes: ["node-4", "node-5"]}
      ...> ]
      iex> EdgeAdmin.Admins.Metadata.Algorithm.compute_assignments(admins, clusters)
      %{
        edge_clusters: %{
          "admin-1" => %{"cluster-b" => ["node-4", "node-5"]},
          "admin-2" => %{"cluster-a" => ["node-1", "node-2", "node-3"]}
        },
        success: true
      }
  """
  def compute_assignments(admins, clusters) do
    # Build cluster lookup map (cluster_id => nodes)
    cluster_nodes_map = Map.new(clusters, fn cluster -> {cluster.id, cluster.nodes} end)

    # Start with empty assignments
    initial_state = %{
      cluster_assignments: %{},
      admin_node_counts: Map.new(admins, fn {admin_id, _} -> {admin_id, 0} end),
      success: true
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
              cluster_assignments: Map.put(state.cluster_assignments, cluster.id, best_admin),
              admin_node_counts:
                Map.update!(state.admin_node_counts, best_admin, &(&1 + cluster_size)),
              success: state.success
            }

          {:error, :no_capacity} ->
            # Cluster couldn't be assigned - mark as failed but continue
            %{state | success: false}
        end
      end)

    # Transform to ETS format: %{admin_id => %{cluster_id => [node_ids]}}
    edge_clusters =
      build_edge_clusters_map(
        intermediate_result.cluster_assignments,
        cluster_nodes_map,
        admins
      )

    %{
      edge_clusters: edge_clusters,
      success: intermediate_result.success
    }
  end

  @doc """
  Bootstrap empty cluster by pre-assigning to best available admin.

  Called by REST API when user creates new cluster, before any nodes join.

  ## Arguments
  - admins: %{admin_id => %{max_capacity: int}}
  - current_assignments: result from compute_assignments/2 (has edge_clusters)
  - cluster_id: cluster to bootstrap

  ## Returns
  {:ok, admin_id} | {:error, :no_capacity}

  ## Example
      iex> admins = %{"admin-1" => %{max_capacity: 200}}
      iex> current = %{edge_clusters: %{"admin-1" => %{}}}
      iex> EdgeAdmin.Admins.Metadata.Algorithm.bootstrap_empty_cluster(admins, current, "cluster-new")
      {:ok, "admin-1"}
  """
  def bootstrap_empty_cluster(admins, current_assignments, cluster_id) do
    # Check if already assigned (search in edge_clusters)
    existing_owner =
      current_assignments.edge_clusters
      |> Enum.find_value(fn {admin_id, clusters} ->
        if Map.has_key?(clusters, cluster_id), do: admin_id
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

      admin_id ->
        {:ok, admin_id}
    end
  end

  # Private helpers

  defp find_best_admin_for_cluster(admins, cluster_assignments, admin_node_counts, cluster_size) do
    # Filter admins that can handle this cluster
    available_admins =
      admins
      |> Enum.filter(fn {admin_id, admin} ->
        can_admin_handle_cluster?(admin, admin_node_counts[admin_id], cluster_size)
      end)
      |> Enum.map(fn {admin_id, _} -> admin_id end)

    case available_admins do
      [] ->
        {:error, :no_capacity}

      admins_list ->
        # Score each admin: prefer fewer clusters managed, then higher remaining capacity
        best_admin =
          admins_list
          |> Enum.min_by(fn admin_id ->
            admin_score(admin_id, admins, cluster_assignments, admin_node_counts)
          end)

        {:ok, best_admin}
    end
  end

  defp can_admin_handle_cluster?(admin, current_node_count, additional_cluster_size) do
    current_node_count + additional_cluster_size <= admin.max_capacity
  end

  defp admin_score(admin_id, admins, cluster_assignments, admin_node_counts) do
    # How many clusters is this admin currently managing?
    clusters_managed =
      cluster_assignments
      |> Enum.count(fn {_cluster_id, assigned_admin} -> assigned_admin == admin_id end)

    # How much remaining capacity does this admin have?
    remaining_capacity = admins[admin_id].max_capacity - admin_node_counts[admin_id]

    # Return tuple: (clusters_managed, -remaining_capacity)
    # Lower is better: prefer fewer clusters, then higher remaining capacity
    {clusters_managed, -remaining_capacity}
  end

  defp build_edge_clusters_map(cluster_assignments, cluster_nodes_map, admins) do
    # Initialize all admins with empty maps
    initial_map = Map.new(admins, fn {admin_id, _} -> {admin_id, %{}} end)

    # Group clusters by admin
    cluster_assignments
    |> Enum.reduce(initial_map, fn {cluster_id, admin_id}, acc ->
      cluster_nodes = Map.get(cluster_nodes_map, cluster_id, [])

      Map.update!(acc, admin_id, fn admin_clusters ->
        Map.put(admin_clusters, cluster_id, cluster_nodes)
      end)
    end)
  end

  @doc """
  Extract flat cluster assignments from edge_clusters format.
  Returns %{cluster_id => admin_id}

  Used internally and for testing.
  """
  def extract_cluster_assignments(edge_clusters) do
    # Flatten edge_clusters back to %{cluster_id => admin_id}
    edge_clusters
    |> Enum.flat_map(fn {admin_id, clusters} ->
      Enum.map(clusters, fn {cluster_id, _nodes} -> {cluster_id, admin_id} end)
    end)
    |> Map.new()
  end

  @doc """
  Calculate admin node counts from edge_clusters format.
  Returns %{admin_id => node_count}

  Used internally and for testing.
  """
  def calculate_admin_node_counts(edge_clusters) do
    # Count total nodes per admin
    edge_clusters
    |> Enum.map(fn {admin_id, clusters} ->
      node_count = clusters |> Map.values() |> Enum.flat_map(& &1) |> length()
      {admin_id, node_count}
    end)
    |> Map.new()
  end
end
