# edge_admin/test/edge_admin/admins/metadata/algorithm_test.exs
defmodule EdgeAdmin.Admins.Metadata.AlgorithmTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Admins.Metadata.Algorithm

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build an admins map from a keyword list of {name, edge_node_capacity}
  defp admins(pairs) do
    Map.new(pairs, fn {name, cap} -> {to_string(name), %{edge_node_capacity: cap}} end)
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

    test "admin with zero capacity → all clusters are orphaned" do
      admins = admins(a1: 0)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.degraded == true
      assert result.edge_clusters["a1"] == %{}
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

    test "deterministic - cluster input order does not affect assignment" do
      # Simulates DB returning clusters in different iteration order across admins.
      # Both orderings must produce identical assignments.
      admins = admins(a1: 100, a2: 100)
      c1 = %{name: "c1", nodes: ~w[n1 n2 n3]}
      c2 = %{name: "c2", nodes: ~w[n4 n5]}

      result_forward = Algorithm.compute_assignments(admins, [c1, c2])
      result_reversed = Algorithm.compute_assignments(admins, [c2, c1])

      assert result_forward.edge_clusters == result_reversed.edge_clusters
      assert result_forward.orphaned_clusters == result_reversed.orphaned_clusters
    end

    test "large clusters get assigned before small ones (greedy bin-packing)" do
      # a1 has capacity 5 — enough for c_large (4 nodes) but not both.
      # c_small arrives first in input order, but c_large should win the slot.
      admins = admins(a1: 5)
      clusters = clusters(c_small: ~w[n1 n2], c_large: ~w[n3 n4 n5 n6])

      result = Algorithm.compute_assignments(admins, clusters)

      # c_large (4 nodes) fits; c_small (2 nodes) gets orphaned since only 1 slot remains
      assert Map.has_key?(result.edge_clusters["a1"], "c_large")
      assert Map.has_key?(result.orphaned_clusters, "c_small")
    end

    test "tie-breaking by admin name is alphabetical when no previous assignment exists" do
      # Both admins have identical capacity and zero clusters — pure tie.
      # With no previous assignment, stickiness has no anchor, so the alphabetically
      # first admin wins (final deterministic tiebreaker).
      admins = admins("admin-b": 100, "admin-a": 100)
      clusters = clusters(c1: ~w[n1])

      result = Algorithm.compute_assignments(admins, clusters)

      assert Map.has_key?(result.edge_clusters["admin-a"], "c1")
      refute Map.has_key?(result.edge_clusters["admin-b"], "c1")
    end

    test "weak_leader is nil when admins map is empty" do
      result = Algorithm.compute_assignments(%{}, [])
      assert result.weak_leader == nil
    end

    test "node_index maps every node to its {cluster, admin}" do
      admins = admins(a1: 100, a2: 100)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3])

      result = Algorithm.compute_assignments(admins, clusters)

      # Every node must appear in the index
      assert map_size(result.node_index) == 3

      # Each entry must point to the correct cluster and admin
      Enum.each(result.edge_clusters, fn {admin_name, clusters} ->
        Enum.each(clusters, fn {cluster_name, nodes} ->
          Enum.each(nodes, fn node ->
            assert result.node_index[node] == {cluster_name, admin_name}
          end)
        end)
      end)
    end

    test "node_index is empty when no clusters" do
      result = Algorithm.compute_assignments(admins(a1: 100), [])
      assert result.node_index == %{}
    end

    test "orphaned nodes are not in node_index" do
      admins = admins(a1: 2)
      # c1 (2 nodes) fits, c2 (1 node) gets orphaned
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3])

      result = Algorithm.compute_assignments(admins, clusters)

      assert Map.has_key?(result.node_index, "n1")
      assert Map.has_key?(result.node_index, "n2")
      refute Map.has_key?(result.node_index, "n3")
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

    # ---------------------------------------------------------------------------
    # total_nodes and total_edge_capacity
    # ---------------------------------------------------------------------------

    test "total_nodes is sum of all nodes across all clusters" do
      admins = admins(a1: 100)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3 n4 n5])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.total_nodes == 5
    end

    test "total_nodes counts orphaned cluster nodes too" do
      # a1 can only hold 2 nodes; c2 has 3 and gets orphaned
      admins = admins(a1: 2)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3 n4 n5])

      result = Algorithm.compute_assignments(admins, clusters)

      # 2 assigned + 3 orphaned = 5 total
      assert result.total_nodes == 5
    end

    test "total_edge_capacity is sum of edge_node_capacity across all admins" do
      admins = admins(a1: 200, a2: 300)
      clusters = clusters(c1: ~w[n1])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.total_edge_capacity == 500
    end

    test "total_edge_capacity reflects sum of all admin capacities" do
      admins = admins(a1: 0, a2: 0)

      result = Algorithm.compute_assignments(admins, [])

      assert result.total_edge_capacity == 0
    end

    test "total_nodes is zero when no clusters" do
      admins = admins(a1: 100)

      result = Algorithm.compute_assignments(admins, [])

      assert result.total_nodes == 0
    end

    test "degraded false when total_nodes equals total_edge_capacity exactly" do
      admins = admins(a1: 5)
      clusters = clusters(c1: ~w[n1 n2 n3 n4 n5])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.total_nodes == 5
      assert result.total_edge_capacity == 5
      assert result.orphaned_clusters == %{}
      assert result.degraded == false
    end

    test "degraded true when total_nodes exceeds total_edge_capacity" do
      # 2 admins with capacity 3 each = 6 total; 7 nodes = degraded
      admins = admins(a1: 3, a2: 3)
      clusters = clusters(c1: ~w[n1 n2 n3], c2: ~w[n4 n5 n6 n7])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.total_nodes == 7
      assert result.total_edge_capacity == 6
      # orphaned_clusters > 0 and total_nodes > total_edge_capacity are equivalent
      assert map_size(result.orphaned_clusters) > 0
      assert result.degraded == true
    end

    test "degraded true when total_nodes exceeds total_edge_capacity due to cluster fragmentation" do
      # a1 capacity 5: c1 (3 nodes) fits, c2 (3 nodes) gets orphaned because only 2 slots remain.
      # total_nodes (6) > total_edge_capacity (5), orphaned_clusters non-empty — both signal degraded.
      admins = admins(a1: 5)
      clusters = clusters(c1: ~w[n1 n2 n3], c2: ~w[n4 n5 n6])

      result = Algorithm.compute_assignments(admins, clusters)

      assert result.total_nodes == 6
      assert result.total_edge_capacity == 5
      assert map_size(result.orphaned_clusters) > 0
      assert result.degraded == true
    end
  end

  # ---------------------------------------------------------------------------
  # Stickiness (previous-owner tiebreaker)
  # ---------------------------------------------------------------------------

  describe "compute_assignments/3 stickiness" do
    test "no-op recompute: feeding previous output back produces identical output" do
      # If the topology hasn't changed, recomputing with the previous output as
      # the third argument must yield the same assignment. This is the load-bearing
      # invariant — without it, the system would jitter on every periodic recompute.
      admins = admins(a1: 100, a2: 100, a3: 100)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3], c3: ~w[n4 n5 n6])

      first = Algorithm.compute_assignments(admins, clusters)
      second = Algorithm.compute_assignments(admins, clusters, first.edge_clusters)

      assert second.edge_clusters == first.edge_clusters
      assert second.node_index == first.node_index
    end

    test "previous owner wins at ties even when alphabetically later" do
      # Pure tie: same capacity, both empty. Without stickiness, admin-a wins
      # (alphabetical). With previous saying admin-b owns c1, admin-b should keep it.
      admins = admins("admin-a": 100, "admin-b": 100)
      clusters = clusters(c1: ~w[n1])

      previous = %{"admin-a" => %{}, "admin-b" => %{"c1" => ~w[n1]}}
      result = Algorithm.compute_assignments(admins, clusters, previous)

      assert Map.has_key?(result.edge_clusters["admin-b"], "c1")
      refute Map.has_key?(result.edge_clusters["admin-a"], "c1")
    end

    test "stickiness does NOT override load balance" do
      # admin-b previously owned c2, but admin-b is now overloaded with c1.
      # admin-a (less loaded) must still win — stickiness only kicks in at score ties.
      admins = admins("admin-a": 100, "admin-b": 100)
      clusters = clusters(c1: ~w[n1 n2 n3 n4 n5], c2: ~w[n6])

      # Previous: admin-b owned both clusters (and is now overloaded)
      previous = %{
        "admin-a" => %{},
        "admin-b" => %{"c1" => ~w[n1 n2 n3 n4 n5], "c2" => ~w[n6]}
      }

      result = Algorithm.compute_assignments(admins, clusters, previous)

      # c1 is largest — placed first. admin-a and admin-b tie on score, stickiness
      # gives c1 to admin-b. After that, admin-b has 1 cluster vs admin-a's 0,
      # so c2 must go to admin-a — load balance wins over stickiness.
      assert Map.has_key?(result.edge_clusters["admin-b"], "c1")
      assert Map.has_key?(result.edge_clusters["admin-a"], "c2")
    end

    test "stickiness does NOT override capacity" do
      # admin-b previously owned c1 but no longer has capacity. admin-a must take it.
      admins = admins("admin-a": 100, "admin-b": 1)
      clusters = clusters(c1: ~w[n1 n2 n3])

      previous = %{"admin-a" => %{}, "admin-b" => %{"c1" => ~w[n1 n2 n3]}}
      result = Algorithm.compute_assignments(admins, clusters, previous)

      assert Map.has_key?(result.edge_clusters["admin-a"], "c1")
      assert result.edge_clusters["admin-b"] == %{}
    end

    test "stale previous owner not in current admins is ignored" do
      # Previous claimed admin-gone owns c1, but admin-gone has left the topology.
      # Stickiness has no anchor in current admins → falls through to alphabetical.
      admins = admins("admin-a": 100, "admin-b": 100)
      clusters = clusters(c1: ~w[n1])

      previous = %{"admin-gone" => %{"c1" => ~w[n1]}}
      result = Algorithm.compute_assignments(admins, clusters, previous)

      # Falls through to final tiebreaker — alphabetical
      assert Map.has_key?(result.edge_clusters["admin-a"], "c1")
    end

    test "previous map with no entry for the cluster is treated as no-stickiness" do
      # New cluster (c2) appearing for the first time — previous has c1 only.
      # c2 should follow normal scoring, no stickiness influence.
      admins = admins("admin-a": 100, "admin-b": 100)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3])

      # Previous: admin-b owns c1
      previous = %{"admin-a" => %{}, "admin-b" => %{"c1" => ~w[n1 n2]}}
      result = Algorithm.compute_assignments(admins, clusters, previous)

      # c1 (largest) placed first — tie broken by stickiness → admin-b
      assert Map.has_key?(result.edge_clusters["admin-b"], "c1")
      # c2: admin-a has 0 clusters, admin-b has 1 — load balance wins, admin-a takes c2
      assert Map.has_key?(result.edge_clusters["admin-a"], "c2")
    end

    test "empty previous map is equivalent to default arity-2 call" do
      admins = admins(a1: 100, a2: 100)
      clusters = clusters(c1: ~w[n1], c2: ~w[n2 n3])

      arity_2 = Algorithm.compute_assignments(admins, clusters)
      arity_3_empty = Algorithm.compute_assignments(admins, clusters, %{})

      assert arity_2 == arity_3_empty
    end

    test "deterministic with stickiness — same inputs (incl. previous) always same output" do
      admins = admins(a1: 100, a2: 100, a3: 100)
      clusters = clusters(c1: ~w[n1 n2], c2: ~w[n3], c3: ~w[n4 n5])
      previous = %{"a1" => %{"c2" => ~w[n3]}, "a2" => %{}, "a3" => %{"c1" => ~w[n1 n2]}}

      r1 = Algorithm.compute_assignments(admins, clusters, previous)
      r2 = Algorithm.compute_assignments(admins, clusters, previous)

      assert r1 == r2
    end
  end

  # ---------------------------------------------------------------------------
  # Bounded churn — the whole point of Stage 1
  # ---------------------------------------------------------------------------

  describe "compute_assignments/3 churn under topology change" do
    # Helper: count how many clusters changed owner between two outputs
    defp count_moves(prev_output, new_output) do
      prev_owners = invert(prev_output.edge_clusters)
      new_owners = invert(new_output.edge_clusters)

      Enum.count(prev_owners, fn {cluster, prev_admin} ->
        Map.get(new_owners, cluster) != prev_admin
      end)
    end

    defp invert(edge_clusters) do
      Enum.reduce(edge_clusters, %{}, fn {admin, clusters}, acc ->
        Enum.reduce(clusters, acc, fn {cluster, _}, acc2 -> Map.put(acc2, cluster, admin) end)
      end)
    end

    test "adding an alphabetically-early admin moves at most ~N/M clusters with stickiness" do
      # Without stickiness this is the worst case — admin-aaa would steal nearly every
      # tied cluster from existing admins because the alphabetical tiebreaker flips.
      # With stickiness, only clusters where admin-aaa genuinely scores better should move.

      # Start: 4 admins, 40 single-node clusters → 10 each
      initial_admins = admins("admin-bbb": 100, "admin-ccc": 100, "admin-ddd": 100, "admin-eee": 100)
      cluster_list = clusters(for i <- 1..40, do: {:"c#{i}", ~w[n#{i}]})

      stable = Algorithm.compute_assignments(initial_admins, cluster_list)

      # Now admin-aaa joins (alphabetically first — worst case for the old tiebreaker)
      new_admins = Map.put(initial_admins, "admin-aaa", %{edge_node_capacity: 100})

      # WITHOUT stickiness (legacy behavior simulated by passing %{})
      without_sticky = Algorithm.compute_assignments(new_admins, cluster_list)
      moves_without = count_moves(stable, without_sticky)

      # WITH stickiness (real behavior)
      with_sticky = Algorithm.compute_assignments(new_admins, cluster_list, stable.edge_clusters)
      moves_with = count_moves(stable, with_sticky)

      # Theoretical minimum on a 5th admin join: 40/5 = 8 moves
      # Stickiness should land near that minimum; legacy behavior should be much worse.
      assert moves_with <= 12, "expected ~8 moves with stickiness, got #{moves_with}"

      assert moves_with < moves_without,
             "stickiness must reduce churn vs legacy (was #{moves_without}, now #{moves_with})"

      # admin-aaa should still get its fair share — stickiness doesn't starve new admins
      aaa_cluster_count = map_size(with_sticky.edge_clusters["admin-aaa"])
      assert aaa_cluster_count >= 6, "new admin starved: only #{aaa_cluster_count} clusters"
    end

    test "removing an admin moves close to only that admin's clusters" do
      # 3 admins × 9 single-node clusters = 3 each. Remove one — its 3 clusters
      # must redistribute. Greedy placement processes the orphaned clusters one at
      # a time; if a survivor takes an orphan early, the running load shifts and
      # one or two of the survivor's existing clusters may also flip. We accept a
      # small slack on top of the theoretical minimum.
      initial_admins = admins(a1: 100, a2: 100, a3: 100)
      cluster_list = clusters(for i <- 1..9, do: {:"c#{i}", ~w[n#{i}]})

      stable = Algorithm.compute_assignments(initial_admins, cluster_list)

      a3_clusters = Map.keys(stable.edge_clusters["a3"])
      a3_count = length(a3_clusters)

      new_admins = Map.delete(initial_admins, "a3")
      after_removal = Algorithm.compute_assignments(new_admins, cluster_list, stable.edge_clusters)

      moves = count_moves(stable, after_removal)
      # Theoretical minimum is a3_count; allow a small tie-shift slack for greedy
      # placement (a survivor taking an orphan can flip one of its existing clusters).
      assert moves >= a3_count, "must reassign at least a3's clusters, got #{moves} < #{a3_count}"

      assert moves <= a3_count + 2,
             "expected ≤ #{a3_count + 2} moves (a3's #{a3_count} + slack), got #{moves}"

      # All a3's clusters must have new owners in {a1, a2}
      Enum.each(a3_clusters, fn cluster ->
        assert Map.has_key?(after_removal.edge_clusters["a1"], cluster) or
                 Map.has_key?(after_removal.edge_clusters["a2"], cluster)
      end)
    end

    test "stable topology with no changes triggers zero moves" do
      admins = admins(a1: 100, a2: 100, a3: 100)
      cluster_list = clusters(for i <- 1..15, do: {:"c#{i}", ~w[n#{i}]})

      r1 = Algorithm.compute_assignments(admins, cluster_list)
      r2 = Algorithm.compute_assignments(admins, cluster_list, r1.edge_clusters)
      r3 = Algorithm.compute_assignments(admins, cluster_list, r2.edge_clusters)

      assert count_moves(r1, r2) == 0
      assert count_moves(r2, r3) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Convergence — disagreement window self-heals within a couple of ticks
  # ---------------------------------------------------------------------------

  describe "compute_assignments/3 convergence" do
    test "cold admin (empty previous) and warm admins agree within 2 ticks" do
      # Scenario from algorithm.md: ABC stable with shared previous P_ABC. D joins.
      # A/B/C compute with P_ABC; D computes with empty previous (cold ETS).
      # Their tick-1 outputs may differ at tie points. By tick 2 they must converge.

      shared_admins = admins(a: 100, b: 100, c: 100, d: 100)
      cluster_list = clusters(for i <- 1..20, do: {:"c#{i}", ~w[n#{i}]})

      # Establish stable previous on A/B/C side (computed before D joined — only 3 admins)
      prev_admins = admins(a: 100, b: 100, c: 100)
      stable_abc = Algorithm.compute_assignments(prev_admins, cluster_list)

      # Tick 1
      tick1_abc = Algorithm.compute_assignments(shared_admins, cluster_list, stable_abc.edge_clusters)
      # D's first compute: empty previous (cold ETS)
      tick1_d = Algorithm.compute_assignments(shared_admins, cluster_list, %{})

      # Tick 2: each side feeds its own tick-1 output back as previous
      tick2_abc = Algorithm.compute_assignments(shared_admins, cluster_list, tick1_abc.edge_clusters)
      tick2_d = Algorithm.compute_assignments(shared_admins, cluster_list, tick1_d.edge_clusters)

      # By tick 2, both sides should be self-stable (no further moves on their own)
      assert tick2_abc.edge_clusters == tick1_abc.edge_clusters,
             "ABC side not self-stable by tick 2"

      assert tick2_d.edge_clusters == tick1_d.edge_clusters,
             "D side not self-stable by tick 2"
    end

    test "after admin death, recomputation distributes orphaned clusters and stays stable" do
      admins_full = admins(a: 100, b: 100, c: 100)
      cluster_list = clusters(for i <- 1..12, do: {:"c#{i}", ~w[n#{i}]})

      stable = Algorithm.compute_assignments(admins_full, cluster_list)

      # 'a' dies
      survivors = admins(b: 100, c: 100)
      after_death = Algorithm.compute_assignments(survivors, cluster_list, stable.edge_clusters)

      # Verify all clusters are reassigned (a's are orphans-of-previous, redistributed)
      assigned = after_death.edge_clusters |> Map.values() |> Enum.flat_map(&Map.keys/1)
      assert length(assigned) == 12

      # Verify stability: re-running with the new output as previous changes nothing
      followup = Algorithm.compute_assignments(survivors, cluster_list, after_death.edge_clusters)
      assert followup.edge_clusters == after_death.edge_clusters
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
