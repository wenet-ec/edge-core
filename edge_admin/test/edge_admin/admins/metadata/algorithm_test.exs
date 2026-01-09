defmodule EdgeAdmin.Admins.Metadata.AlgorithmTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Admins.Metadata.Algorithm

  describe "compute_assignments/2" do
    test "distributes clusters evenly across admins with equal capacity" do
      admins = %{
        "admin-1" => %{max_capacity: 100},
        "admin-2" => %{max_capacity: 100}
      }

      clusters = [
        %{name: "cluster-a", nodes: ["node-1", "node-2"]},
        %{name: "cluster-b", nodes: ["node-3", "node-4"]},
        %{name: "cluster-c", nodes: ["node-5", "node-6"]},
        %{name: "cluster-d", nodes: ["node-7", "node-8"]}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      # Each admin should get 2 clusters
      assert map_size(result.edge_clusters["admin-1"]) == 2
      assert map_size(result.edge_clusters["admin-2"]) == 2

      # No orphaned clusters
      assert result.orphaned_clusters == %{}
      assert result.degraded == false

      # Total nodes distributed correctly (4 nodes per admin)
      admin1_nodes = result.edge_clusters["admin-1"] |> Map.values() |> List.flatten()
      admin2_nodes = result.edge_clusters["admin-2"] |> Map.values() |> List.flatten()

      assert length(admin1_nodes) == 4
      assert length(admin2_nodes) == 4
    end

    test "assigns all clusters to single admin when one admin available" do
      admins = %{
        "admin-solo" => %{max_capacity: 200}
      }

      clusters = [
        %{name: "cluster-a", nodes: ["node-1", "node-2", "node-3"]},
        %{name: "cluster-b", nodes: ["node-4", "node-5"]}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      # All clusters go to the only admin
      assert map_size(result.edge_clusters["admin-solo"]) == 2
      assert Map.has_key?(result.edge_clusters["admin-solo"], "cluster-a")
      assert Map.has_key?(result.edge_clusters["admin-solo"], "cluster-b")

      assert result.orphaned_clusters == %{}
      assert result.degraded == false
    end

    test "marks as degraded when cluster exceeds all admin capacities" do
      admins = %{
        "admin-1" => %{max_capacity: 50},
        "admin-2" => %{max_capacity: 50}
      }

      clusters = [
        %{name: "cluster-small", nodes: Enum.map(1..10, &"node-#{&1}")},
        # This cluster is too big for any admin
        %{name: "cluster-huge", nodes: Enum.map(1..100, &"huge-node-#{&1}")}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      # Small cluster assigned
      assert result.edge_clusters["admin-1"]["cluster-small"] ||
               result.edge_clusters["admin-2"]["cluster-small"]

      # Huge cluster orphaned
      assert Map.has_key?(result.orphaned_clusters, "cluster-huge")
      assert length(result.orphaned_clusters["cluster-huge"]) == 100

      # System is degraded
      assert result.degraded == true
    end

    test "handles empty cluster list" do
      admins = %{
        "admin-1" => %{max_capacity: 100}
      }

      clusters = []

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.edge_clusters["admin-1"] == %{}
      assert result.orphaned_clusters == %{}
      assert result.degraded == false
    end

    test "handles clusters with no nodes (empty clusters)" do
      admins = %{
        "admin-1" => %{max_capacity: 100},
        "admin-2" => %{max_capacity: 100}
      }

      clusters = [
        %{name: "cluster-empty-1", nodes: []},
        %{name: "cluster-empty-2", nodes: []},
        %{name: "cluster-with-nodes", nodes: ["node-1", "node-2"]}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      # All clusters should be assigned (empty clusters have size 0)
      total_clusters =
        map_size(result.edge_clusters["admin-1"]) +
          map_size(result.edge_clusters["admin-2"])

      assert total_clusters == 3
      assert result.orphaned_clusters == %{}
      assert result.degraded == false
    end

    test "prefers admin with fewer clusters when capacity is equal" do
      admins = %{
        "admin-1" => %{max_capacity: 100},
        "admin-2" => %{max_capacity: 100}
      }

      # First cluster goes to admin-1 (both have 0 clusters)
      # Second cluster goes to admin-2 (both have capacity, tie-break)
      # Third cluster should go to admin with fewer clusters
      clusters = [
        %{name: "cluster-1", nodes: ["node-1"]},
        %{name: "cluster-2", nodes: ["node-2"]},
        %{name: "cluster-3", nodes: ["node-3"]}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      # Should distribute: 2 to one admin, 1 to the other
      admin1_count = map_size(result.edge_clusters["admin-1"])
      admin2_count = map_size(result.edge_clusters["admin-2"])

      assert admin1_count + admin2_count == 3
      assert Enum.sort([admin1_count, admin2_count]) == [1, 2]
    end

    test "respects capacity constraints during distribution" do
      admins = %{
        "admin-small" => %{max_capacity: 10},
        "admin-large" => %{max_capacity: 100}
      }

      clusters = [
        %{name: "cluster-1", nodes: Enum.map(1..5, &"node-#{&1}")},
        %{name: "cluster-2", nodes: Enum.map(1..5, &"node-#{&1}")},
        # This would exceed admin-small's capacity
        %{name: "cluster-3", nodes: Enum.map(1..5, &"node-#{&1}")}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      # Calculate actual node counts
      small_nodes =
        result.edge_clusters["admin-small"] |> Map.values() |> List.flatten() |> length()

      large_nodes =
        result.edge_clusters["admin-large"] |> Map.values() |> List.flatten() |> length()

      # admin-small should not exceed capacity
      assert small_nodes <= 10
      # admin-large should handle the rest
      assert large_nodes + small_nodes == 15
      assert result.degraded == false
    end

    test "deterministic assignment (same input produces same output)" do
      admins = %{
        "admin-1" => %{max_capacity: 100},
        "admin-2" => %{max_capacity: 100}
      }

      clusters = [
        %{name: "cluster-a", nodes: ["node-1", "node-2"]},
        %{name: "cluster-b", nodes: ["node-3", "node-4"]},
        %{name: "cluster-c", nodes: ["node-5"]}
      ]

      result1 = Algorithm.compute_assignments(admins, clusters)
      result2 = Algorithm.compute_assignments(admins, clusters)

      # Results should be identical
      assert result1 == result2
    end

    test "handles multiple orphaned clusters" do
      admins = %{
        "admin-tiny" => %{max_capacity: 5}
      }

      clusters = [
        %{name: "cluster-ok", nodes: ["node-1", "node-2"]},
        %{name: "cluster-too-big-1", nodes: Enum.map(1..10, &"node-#{&1}")},
        %{name: "cluster-too-big-2", nodes: Enum.map(1..20, &"node-#{&1}")}
      ]

      result = Algorithm.compute_assignments(admins, clusters)

      # One cluster assigned
      assert map_size(result.edge_clusters["admin-tiny"]) == 1
      assert result.edge_clusters["admin-tiny"]["cluster-ok"] == ["node-1", "node-2"]

      # Two clusters orphaned
      assert map_size(result.orphaned_clusters) == 2
      assert Map.has_key?(result.orphaned_clusters, "cluster-too-big-1")
      assert Map.has_key?(result.orphaned_clusters, "cluster-too-big-2")
      assert result.degraded == true
    end
  end

  describe "bootstrap_empty_cluster/3" do
    test "assigns empty cluster to admin with most remaining capacity" do
      admins = %{
        "admin-1" => %{max_capacity: 100},
        "admin-2" => %{max_capacity: 200}
      }

      current = %{
        edge_clusters: %{
          "admin-1" => %{},
          "admin-2" => %{}
        }
      }

      assert {:ok, "admin-2"} =
               Algorithm.bootstrap_empty_cluster(admins, current, "new-cluster")
    end

    test "returns existing owner if cluster already assigned" do
      admins = %{
        "admin-1" => %{max_capacity: 100},
        "admin-2" => %{max_capacity: 100}
      }

      current = %{
        edge_clusters: %{
          "admin-1" => %{"existing-cluster" => []},
          "admin-2" => %{}
        }
      }

      assert {:ok, "admin-1"} =
               Algorithm.bootstrap_empty_cluster(admins, current, "existing-cluster")
    end

    test "allows empty cluster even when admin is at capacity" do
      admins = %{
        "admin-1" => %{max_capacity: 10}
      }

      # Admin already at capacity with 10 nodes
      current = %{
        edge_clusters: %{
          "admin-1" => %{
            "cluster-1" => Enum.map(1..10, &"node-#{&1}")
          }
        }
      }

      # Empty clusters (size 0) don't consume capacity, so should succeed
      assert {:ok, "admin-1"} =
               Algorithm.bootstrap_empty_cluster(admins, current, "new-cluster")
    end

    test "prefers admin with fewer clusters when capacity equal" do
      admins = %{
        "admin-1" => %{max_capacity: 100},
        "admin-2" => %{max_capacity: 100}
      }

      # admin-1 has 1 cluster, admin-2 has 0
      current = %{
        edge_clusters: %{
          "admin-1" => %{"existing" => ["node-1"]},
          "admin-2" => %{}
        }
      }

      # Should prefer admin-2 (fewer clusters)
      assert {:ok, "admin-2"} =
               Algorithm.bootstrap_empty_cluster(admins, current, "new-cluster")
    end
  end

  describe "extract_cluster_assignments/1" do
    test "flattens edge_clusters format to cluster => admin map" do
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

    test "handles empty clusters" do
      edge_clusters = %{
        "admin-1" => %{},
        "admin-2" => %{}
      }

      result = Algorithm.extract_cluster_assignments(edge_clusters)

      assert result == %{}
    end
  end

  describe "calculate_admin_node_counts/1" do
    test "sums total nodes per admin" do
      edge_clusters = %{
        "admin-1" => %{
          "cluster-a" => ["node-1", "node-2", "node-3"],
          "cluster-b" => ["node-4", "node-5"]
        },
        "admin-2" => %{
          "cluster-c" => ["node-6"]
        }
      }

      result = Algorithm.calculate_admin_node_counts(edge_clusters)

      assert result == %{
               "admin-1" => 5,
               "admin-2" => 1
             }
    end

    test "handles admins with no nodes" do
      edge_clusters = %{
        "admin-1" => %{},
        "admin-2" => %{"cluster-a" => ["node-1"]}
      }

      result = Algorithm.calculate_admin_node_counts(edge_clusters)

      assert result == %{
               "admin-1" => 0,
               "admin-2" => 1
             }
    end

    test "handles empty cluster lists" do
      edge_clusters = %{
        "admin-1" => %{"cluster-empty" => []},
        "admin-2" => %{}
      }

      result = Algorithm.calculate_admin_node_counts(edge_clusters)

      assert result == %{
               "admin-1" => 0,
               "admin-2" => 0
             }
    end
  end
end
