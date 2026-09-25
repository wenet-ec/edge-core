# edge_admin/test/edge_admin/nodes/checks/node_limit_below_count_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.NodeLimitBelowCountCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Checks.NodeLimitBelowCountCheck
  alias EdgeAdmin.Test.Fixtures
  # helpers

  defp insert_cluster(overrides \\ %{}), do: Fixtures.insert_cluster!(overrides)
  defp insert_node(cluster_id), do: Fixtures.insert_node!(cluster_id)

  # check/2 — nil new_limit

  describe "check/2 — nil new_limit (removing the cap)" do
    test "nil new_limit always returns :ok regardless of node count" do
      cluster = insert_cluster()
      assert :ok = NodeLimitBelowCountCheck.check(cluster, nil)
    end

    test "nil new_limit returns :ok even when cluster has nodes" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert :ok = NodeLimitBelowCountCheck.check(cluster, nil)
    end
  end

  # check/2 — new_limit >= node count

  describe "check/2 — new_limit accommodates existing nodes" do
    test "new_limit equal to node count returns :ok" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert :ok = NodeLimitBelowCountCheck.check(cluster, 2)
    end

    test "new_limit greater than node count returns :ok" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      assert :ok = NodeLimitBelowCountCheck.check(cluster, 5)
    end

    test "empty cluster with any positive limit returns :ok" do
      cluster = insert_cluster()
      assert :ok = NodeLimitBelowCountCheck.check(cluster, 1)
    end
  end

  # check/2 — new_limit < node count

  describe "check/2 — new_limit below current node count" do
    test "new_limit below node count returns a conflict" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = NodeLimitBelowCountCheck.check(cluster, 1)
      assert reason == "node limit cannot be less than current node count (2)"
    end

    test "zero new_limit is always below a non-empty cluster" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = NodeLimitBelowCountCheck.check(cluster, 0)
      assert reason == "node limit cannot be less than current node count (1)"
    end
  end
end
