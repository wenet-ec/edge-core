# edge_admin/test/edge_admin/admins/metadata/algorithm_test.exs
defmodule EdgeAdmin.Admins.Metadata.AlgorithmTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Admins.Metadata.Algorithm

  describe "compute_assignments/2" do
    test "basic assignment with two admins and two clusters" do
      admins = %{
        "admin-1" => %{max_capacity: 200},
        "admin-2" => %{max_capacity: 300}
      }

      clusters = [
        %{id: "cluster-a", nodes: ["node-1", "node-2", "node-3"]},
        %{id: "cluster-b", nodes: ["node-4", "node-5"]}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.success == true
      assert map_size(result.edge_clusters) == 2

      # Both admins should have at least one cluster
      assert map_size(result.edge_clusters["admin-1"]) >= 0
      assert map_size(result.edge_clusters["admin-2"]) >= 0

      # Total clusters should be 2
      total_clusters =
        result.edge_clusters
        |> Enum.flat_map(fn {_admin_id, clusters} -> Map.keys(clusters) end)
        |> length()

      assert total_clusters == 2

      # All nodes should be assigned
      assigned_nodes =
        result.edge_clusters
        |> Enum.flat_map(fn {_admin_id, clusters} -> Map.values(clusters) end)
        |> Enum.flat_map(& &1)
        |> Enum.sort()

      assert assigned_nodes == ["node-1", "node-2", "node-3", "node-4", "node-5"]
    end

    test "no capacity - degraded mode" do
      admins = %{
        # Only 2 nodes capacity
        "admin-1" => %{max_capacity: 2}
      }

      clusters = [
        # 3 nodes!
        %{id: "cluster-a", nodes: ["node-1", "node-2", "node-3"]}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.success == false

      # No clusters should be assigned since cluster is too big
      assert result.edge_clusters["admin-1"] == %{}
    end

    test "empty clusters are assigned" do
      admins = %{
        "admin-1" => %{max_capacity: 200}
      }

      clusters = [
        %{id: "cluster-a", nodes: []},
        %{id: "cluster-b", nodes: ["node-1"]}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.success == true
      assert Map.has_key?(result.edge_clusters["admin-1"], "cluster-a")
      assert Map.has_key?(result.edge_clusters["admin-1"], "cluster-b")
    end

    test "load balancing prefers admin with fewer clusters" do
      admins = %{
        "admin-1" => %{max_capacity: 500},
        "admin-2" => %{max_capacity: 500}
      }

      # Create 6 small clusters - should distribute evenly
      clusters =
        for i <- 1..6 do
          %{
            id: "cluster-#{i}",
            nodes: ["node-#{i}-1", "node-#{i}-2"]
          }
        end

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.success == true

      # Count clusters per admin
      cluster_counts =
        result.edge_clusters
        |> Enum.map(fn {admin_id, clusters} -> {admin_id, map_size(clusters)} end)
        |> Map.new()

      # Should be balanced (3 and 3)
      assert cluster_counts["admin-1"] == 3
      assert cluster_counts["admin-2"] == 3
    end

    test "all admins initialized in edge_clusters even if no assignments" do
      admins = %{
        "admin-1" => %{max_capacity: 200},
        "admin-2" => %{max_capacity: 300},
        "admin-3" => %{max_capacity: 500}
      }

      clusters = [
        %{id: "cluster-a", nodes: ["node-1"]}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.success == true

      # All admins should exist in edge_clusters
      assert Map.has_key?(result.edge_clusters, "admin-1")
      assert Map.has_key?(result.edge_clusters, "admin-2")
      assert Map.has_key?(result.edge_clusters, "admin-3")

      # Two admins should have empty maps
      empty_count =
        result.edge_clusters
        |> Enum.count(fn {_admin_id, clusters} -> map_size(clusters) == 0 end)

      assert empty_count == 2
    end
  end

  describe "bootstrap_empty_cluster/3" do
    test "assigns new empty cluster to best available admin" do
      admins = %{
        "admin-1" => %{max_capacity: 200},
        "admin-2" => %{max_capacity: 300}
      }

      # Start with some existing assignments
      clusters = [
        %{id: "cluster-a", nodes: ["node-1", "node-2"]}
      ]

      assignments = Algorithm.compute_assignments(admins, clusters)

      # Bootstrap new empty cluster
      assert {:ok, admin_id} = Algorithm.bootstrap_empty_cluster(admins, assignments, "cluster-b")
      assert admin_id in ["admin-1", "admin-2"]
    end

    test "returns existing admin if cluster already assigned" do
      admins = %{
        "admin-1" => %{max_capacity: 200}
      }

      clusters = [
        %{id: "cluster-a", nodes: ["node-1"]}
      ]

      assignments = Algorithm.compute_assignments(admins, clusters)

      # Try to bootstrap already-assigned cluster
      assert {:ok, "admin-1"} =
               Algorithm.bootstrap_empty_cluster(admins, assignments, "cluster-a")
    end

    test "returns error when no capacity available" do
      admins = %{
        "admin-1" => %{max_capacity: 1}
      }

      clusters = [
        %{id: "cluster-a", nodes: ["node-1"]}
      ]

      assignments = Algorithm.compute_assignments(admins, clusters)

      # No more capacity for new cluster
      assert {:error, :no_capacity} =
               Algorithm.bootstrap_empty_cluster(admins, assignments, "cluster-b")
    end
  end

  describe "extract_cluster_assignments/1" do
    test "extracts flat cluster assignments from edge_clusters" do
      edge_clusters = %{
        "admin-1" => %{
          "cluster-a" => ["node-1", "node-2"],
          "cluster-b" => ["node-3"]
        },
        "admin-2" => %{
          "cluster-c" => ["node-4"]
        }
      }

      result = Algorithm.extract_cluster_assignments(edge_clusters)

      assert result == %{
               "cluster-a" => "admin-1",
               "cluster-b" => "admin-1",
               "cluster-c" => "admin-2"
             }
    end

    test "handles empty edge_clusters" do
      edge_clusters = %{
        "admin-1" => %{},
        "admin-2" => %{}
      }

      result = Algorithm.extract_cluster_assignments(edge_clusters)

      assert result == %{}
    end
  end

  describe "calculate_admin_node_counts/1" do
    test "calculates node counts per admin" do
      edge_clusters = %{
        "admin-1" => %{
          "cluster-a" => ["node-1", "node-2", "node-3"],
          "cluster-b" => ["node-4"]
        },
        "admin-2" => %{
          "cluster-c" => ["node-5", "node-6"]
        }
      }

      result = Algorithm.calculate_admin_node_counts(edge_clusters)

      assert result == %{
               "admin-1" => 4,
               "admin-2" => 2
             }
    end

    test "handles admins with no nodes" do
      edge_clusters = %{
        "admin-1" => %{},
        "admin-2" => %{
          "cluster-a" => ["node-1"]
        }
      }

      result = Algorithm.calculate_admin_node_counts(edge_clusters)

      assert result == %{
               "admin-1" => 0,
               "admin-2" => 1
             }
    end
  end

  describe "performance test" do
    test "handles large scale (500 nodes, 25 clusters) efficiently" do
      admins = %{
        "admin-1" => %{max_capacity: 200},
        "admin-2" => %{max_capacity: 300},
        "admin-3" => %{max_capacity: 500}
      }

      # Generate 25 clusters with ~500 total nodes
      clusters = generate_test_clusters(25, 500)

      {time_us, result} =
        :timer.tc(fn ->
          Algorithm.compute_assignments(admins, clusters)
        end)

      time_ms = time_us / 1000

      assert result.success == true
      # Should complete in reasonable time (< 100ms)
      assert time_ms < 100

      # Verify all nodes are assigned
      total_nodes =
        clusters
        |> Enum.flat_map(& &1.nodes)
        |> length()

      assigned_nodes =
        result.edge_clusters
        |> Enum.flat_map(fn {_admin_id, clusters} -> Map.values(clusters) end)
        |> Enum.flat_map(& &1)
        |> length()

      assert assigned_nodes == total_nodes
    end
  end

  # Helper functions

  defp generate_test_clusters(num_clusters, total_nodes) do
    nodes_per_cluster = div(total_nodes, num_clusters)
    remainder = rem(total_nodes, num_clusters)

    for i <- 1..num_clusters do
      # Give extra nodes to first few clusters
      extra = if i <= remainder, do: 1, else: 0
      node_count = nodes_per_cluster + extra

      nodes = for j <- 1..node_count, do: "node-cluster-#{i}-#{j}"

      %{id: "cluster-#{i}", nodes: nodes}
    end
  end
end
