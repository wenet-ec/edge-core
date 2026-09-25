# edge_admin/test/edge_admin/nodes/checks/alias_cluster_matches_node_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.AliasClusterMatchesNodeCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Checks.AliasClusterMatchesNodeCheck
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Test.Fixtures

  defp insert_cluster(id, name), do: Fixtures.insert_cluster!(%{id: id, name: name})

  defp insert_node(id, cluster_id), do: Fixtures.insert_node!(cluster_id, %{id: id})

  test "accepts an alias whose cluster matches the node cluster" do
    cluster = insert_cluster(Ecto.UUID.generate(), "cluster-match")
    node = insert_node(Ecto.UUID.generate(), cluster.id)

    changeset = Alias.changeset(%Alias{}, %{name: "web", node_id: node.id, cluster_id: cluster.id})

    assert :ok = AliasClusterMatchesNodeCheck.check(changeset)
  end

  test "rejects an alias whose cluster differs from the node cluster" do
    node_cluster = insert_cluster(Ecto.UUID.generate(), "cluster-node")
    other_cluster = insert_cluster(Ecto.UUID.generate(), "cluster-other")
    node = insert_node(Ecto.UUID.generate(), node_cluster.id)

    changeset =
      Alias.changeset(%Alias{}, %{name: "web", node_id: node.id, cluster_id: other_cluster.id})

    assert {:error, {:conflict, reason}} = AliasClusterMatchesNodeCheck.check(changeset)
    assert reason == "alias cluster must match the node's current cluster"
  end
end
