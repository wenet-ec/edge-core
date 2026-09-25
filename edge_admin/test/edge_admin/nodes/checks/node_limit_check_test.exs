# edge_admin/test/edge_admin/nodes/checks/node_limit_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.NodeLimitCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Checks.NodeLimitCheck
  alias EdgeAdmin.Test.Fixtures
  # helpers

  defp insert_cluster(overrides), do: Fixtures.insert_cluster!(overrides)
  defp insert_node(cluster_id), do: Fixtures.insert_node!(cluster_id)

  # check/1 — no limit

  describe "check/1 — cluster with no node limit" do
    test "cluster with nil node_limit always returns :ok" do
      cluster = insert_cluster(%{node_limit: nil})
      assert :ok = NodeLimitCheck.check(cluster)
    end

    test "cluster with nil node_limit returns :ok even when nodes exist" do
      cluster = insert_cluster(%{node_limit: nil})
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert :ok = NodeLimitCheck.check(cluster)
    end
  end

  # check/1 — with limit, below limit

  describe "check/1 — cluster with node limit, below limit" do
    test "empty cluster with limit returns :ok" do
      cluster = insert_cluster(%{node_limit: 3})
      assert :ok = NodeLimitCheck.check(cluster)
    end

    test "cluster with nodes below limit returns :ok" do
      cluster = insert_cluster(%{node_limit: 3})
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert :ok = NodeLimitCheck.check(cluster)
    end

    test "cluster with one node and limit of 2 returns :ok" do
      cluster = insert_cluster(%{node_limit: 2})
      insert_node(cluster.id)
      assert :ok = NodeLimitCheck.check(cluster)
    end
  end

  # check/1 — at or above limit

  describe "check/1 — cluster at node limit" do
    test "cluster at exactly the limit returns conflict error" do
      cluster = insert_cluster(%{node_limit: 2})
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = NodeLimitCheck.check(cluster)
      assert reason =~ "node limit"
      assert reason =~ "2"
    end

    test "cluster exceeding limit returns conflict error" do
      cluster = insert_cluster(%{node_limit: 1})
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = NodeLimitCheck.check(cluster)
      assert reason =~ "node limit"
    end

    test "error message includes the limit value" do
      cluster = insert_cluster(%{node_limit: 5})
      for _ <- 1..5, do: insert_node(cluster.id)
      {:error, {:conflict, reason}} = NodeLimitCheck.check(cluster)
      assert reason =~ "5"
    end
  end
end
