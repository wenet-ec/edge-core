defmodule EdgeAdmin.Admins.Metadata.AlgorithmTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Admins.Metadata.Algorithm

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build an admins map from a keyword list of {name, max_capacity}
  defp admins(pairs) do
    Map.new(pairs, fn {name, cap} -> {to_string(name), %{max_capacity: cap}} end)
  end

  # Build a cluster list from a keyword list of {name, [node_names]}
  defp clusters(pairs) do
    Enum.map(pairs, fn {name, nodes} ->
      %{name: to_string(name), nodes: Enum.map(nodes, &to_string/1)}
    end)
  end

  # ---------------------------------------------------------------------------
  # compute_assignments/2
  # ---------------------------------------------------------------------------

  describe "compute_assignments/2" do
    test "single admin gets all clusters" do
      admins = admins(a1: 100)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.degraded == false
      assert result.orphaned_clusters == %{}

      a1_clusters = result.edge_clusters["a1"]
      assert Map.has_key?(a1_clusters, "c1")
      assert Map.has_key?(a1_clusters, "c2")
      assert Enum.sort(a1_clusters["c1"]) == ~w[n1 n2]
      assert a1_clusters["c2"] == ~w[n3]
    end

    test "no admins → all clusters are orphaned" do
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3])

      result = Algorithm.compute_assignments(%{}, clusters)

      assert result.degraded == true
      assert result.edge_clusters == %{}
      assert Map.has_key?(result.orphaned_clusters, "c1")
      assert Map.has_key?(result.orphaned_clusters, "c2")
    end

    test "no clusters → all admins have empty maps, not degraded" do
      admins = admins(a1: 100, a2: 200)

      result = Algorithm.compute_assignments(admins, [])

      assert result.degraded == false
      assert result.orphaned_clusters == %{}
      assert result.edge_clusters["a1"] == %{}
      assert result.edge_clusters["a2"] == %{}
    end

    test "cluster too large for any admin is orphaned, degraded is set" do
      admins = admins(a1: 2)
      clusters = clusters(big: ~w[n1 n2 n3])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.degraded == true
      assert Map.has_key?(result.orphaned_clusters, "big")
      assert result.orphaned_clusters["big"] == ~w[n1 n2 n3]
    end

    test "cluster fits exactly at capacity boundary" do
      admins = admins(a1: 3)
      clusters = clusters(c1: ~w[n1 n2 n3])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.degraded == false
      assert result.edge_clusters["a1"]["c1"] == ~w[n1 n2 n3]
    end

    test "prefers admin with fewer clusters (load balancing)" do
      # a1 already has a cluster assigned before a2 in this scenario.
      # With two equal-capacity admins and two clusters, each should get one.
      admins = admins(a1: 100, a2: 100)
      clusters = clusters(c1: ~w[n1], c2: ~w[n2])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.degraded == false

      # Each admin should own exactly one cluster
      a1_count = map_size(result.edge_clusters["a1"])
      a2_count = map_size(result.edge_clusters["a2"])
      assert a1_count + a2_count == 2
      assert a1_count == 1
      assert a2_count == 1
    end

    test "prefers admin with higher remaining capacity when cluster count is equal" do
      # a2 has more capacity, so a2 should get the cluster that fills first
      admins = admins(a1: 10, a2: 100)
      clusters = clusters(c1: ~w[n1 n2 n3 n4 n5])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.degraded == false
      # a2 should get the larger cluster since it has more remaining capacity
      assert Map.has_key?(result.edge_clusters["a2"], "c1")
      refute Map.has_key?(result.edge_clusters["a1"], "c1")
    end

    test "deterministic - same inputs always produce same outputs" do
      admins = admins(a1: 100, a2: 200, a3: 150)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3], c3: ~w[n4 n5 n6])

      result1 = Algorithm.compute_assignments(admins, clusters)
      result2 = Algorithm.compute_assignments(admins, clusters)

      assert result1 == result2
    end

    test "empty cluster (no nodes) is assigned without consuming capacity" do
      admins = admins(a1: 0)
      clusters = clusters(c1: [])

      result = Algorithm.compute_assignments(admins, clusters)

      # Empty cluster costs 0 nodes, so even zero-capacity admin can take it
      assert result.degraded == false
      assert result.edge_clusters["a1"]["c1"] == []
    end

    test "all clusters orphaned when capacity exhausted, degraded true" do
      admins = admins(a1: 2)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.degraded == true

      total_assigned =
        result.edge_clusters
        |> Map.values()
        |> Enum.flat_map(&Map.keys/1)
        |> length()

      total_orphaned = map_size(result.orphaned_clusters)

      assert total_assigned + total_orphaned == 2
    end

    test "node names are preserved exactly in output" do
      admins = admins(a1: 100)
      node_names = ["node-abc123", "node-def456", "node-ghi789"]
      clusters = [%{name: "cluster-prod", nodes: node_names}]

      result = Algorithm.compute_assignments(admins, clusters)

      assert Enum.sort(result.edge_clusters["a1"]["cluster-prod"]) ==
               Enum.sort(node_names)
    end
  end

  # ---------------------------------------------------------------------------
  # bootstrap_empty_cluster/3
  # ---------------------------------------------------------------------------

  describe "bootstrap_empty_cluster/3" do
    test "assigns empty cluster to best available admin" do
      admins = admins(a1: 100)
      current = %{edge_clusters: %{"a1" => %{}}}

      assert {:ok, "a1"} = Algorithm.bootstrap_empty_cluster(admins, current, "new-cluster")
    end

    test "returns existing owner if cluster already assigned" do
      admins = admins(a1: 100, a2: 100)
      current = %{edge_clusters: %{"a1" => %{"existing" => []}, "a2" => %{}}}

      assert {:ok, "a1"} = Algorithm.bootstrap_empty_cluster(admins, current, "existing")
    end

    test "returns error when no admin has capacity" do
      # No admins at all → no one can take the cluster
      result = Algorithm.bootstrap_empty_cluster(%{}, %{edge_clusters: %{}}, "new-cluster")
      assert result == {:error, :no_capacity}
    end

    test "prefers admin with fewer existing clusters" do
      admins = admins(a1: 100, a2: 100)

      # a1 already manages one cluster, a2 manages none
      current = %{
        edge_clusters: %{
          "a1" => %{"existing-cluster" => ~w[n1]},
          "a2" => %{}
        }
      }

      assert {:ok, "a2"} = Algorithm.bootstrap_empty_cluster(admins, current, "new-cluster")
    end
  end

  # ---------------------------------------------------------------------------
  # extract_cluster_assignments/1
  # ---------------------------------------------------------------------------

  describe "extract_cluster_assignments/1" do
    test "flattens edge_clusters to cluster_name => admin_name map" do
      edge_clusters = %{
        "a1" => %{"c1" => ~w[n1], "c2" => ~w[n2]},
        "a2" => %{"c3" => ~w[n3]}
      }

      result = Algorithm.extract_cluster_assignments(edge_clusters)

      assert result == %{"c1" => "a1", "c2" => "a1", "c3" => "a2"}
    end

    test "empty edge_clusters returns empty map" do
      assert Algorithm.extract_cluster_assignments(%{}) == %{}
    end

    test "admin with no clusters contributes nothing" do
      edge_clusters = %{"a1" => %{}, "a2" => %{"c1" => ~w[n1]}}
      result = Algorithm.extract_cluster_assignments(edge_clusters)
      assert result == %{"c1" => "a2"}
    end
  end

  # ---------------------------------------------------------------------------
  # calculate_admin_node_counts/1
  # ---------------------------------------------------------------------------

  describe "calculate_admin_node_counts/1" do
    test "counts total nodes per admin across all clusters" do
      edge_clusters = %{
        "a1" => %{"c1" => ~w[n1 n2], "c2" => ~w[n3]},
        "a2" => %{"c3" => ~w[n4 n5 n6]}
      }

      result = Algorithm.calculate_admin_node_counts(edge_clusters)

      assert result == %{"a1" => 3, "a2" => 3}
    end

    test "admin with no clusters has count of zero" do
      edge_clusters = %{"a1" => %{}, "a2" => %{"c1" => ~w[n1]}}
      result = Algorithm.calculate_admin_node_counts(edge_clusters)
      assert result == %{"a1" => 0, "a2" => 1}
    end

    test "empty input returns empty map" do
      assert Algorithm.calculate_admin_node_counts(%{}) == %{}
    end
  end
end
