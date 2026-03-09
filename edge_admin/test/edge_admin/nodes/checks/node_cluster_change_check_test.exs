# edge_admin/test/edge_admin/nodes/checks/node_cluster_change_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.NodeClusterChangeCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Checks.NodeClusterChangeCheck
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node

  # ---------------------------------------------------------------------------
  # check/2 — pure struct pattern match, no DB
  # ---------------------------------------------------------------------------

  describe "check/2 — same cluster" do
    test "node already in the target cluster returns conflict error" do
      cluster_id = Ecto.UUID.generate()
      node = %Node{cluster_id: cluster_id}
      cluster = %Cluster{id: cluster_id}
      assert {:error, {:unprocessable, reason}} = NodeClusterChangeCheck.check(node, cluster)
      assert reason =~ "already"
    end
  end

  describe "check/2 — different cluster" do
    test "node moving to a different cluster returns :ok" do
      node = %Node{cluster_id: Ecto.UUID.generate()}
      cluster = %Cluster{id: Ecto.UUID.generate()}
      assert :ok = NodeClusterChangeCheck.check(node, cluster)
    end

    test "node with nil cluster_id moving to any cluster returns :ok" do
      node = %Node{cluster_id: nil}
      cluster = %Cluster{id: Ecto.UUID.generate()}
      assert :ok = NodeClusterChangeCheck.check(node, cluster)
    end
  end
end
