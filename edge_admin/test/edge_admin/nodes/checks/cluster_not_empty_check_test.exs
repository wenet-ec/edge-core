# edge_admin/test/edge_admin/nodes/checks/cluster_not_empty_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.ClusterNotEmptyCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Checks.ClusterNotEmptyCheck
  alias EdgeAdmin.Test.Fixtures
  # helpers

  defp insert_cluster, do: Fixtures.insert_cluster!()
  defp insert_node(cluster_id), do: Fixtures.insert_node!(cluster_id)

  # check/1 — empty cluster

  describe "check/1 — empty cluster" do
    test "cluster with no nodes returns :ok" do
      cluster = insert_cluster()
      assert :ok = ClusterNotEmptyCheck.check(cluster)
    end
  end

  # check/1 — cluster with nodes

  describe "check/1 — cluster with nodes" do
    test "cluster with one node returns conflict error" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = ClusterNotEmptyCheck.check(cluster)
      assert reason =~ "1"
    end

    test "cluster with multiple nodes returns conflict error with count" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = ClusterNotEmptyCheck.check(cluster)
      assert reason =~ "3"
    end

    test "error message instructs to remove nodes first" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      {:error, {:conflict, reason}} = ClusterNotEmptyCheck.check(cluster)
      assert reason =~ "remove"
    end
  end
end
