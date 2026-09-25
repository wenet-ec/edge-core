# edge_admin/test/edge_admin/nodes/resources/alias_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.AliasResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.AliasResources
  alias EdgeAdmin.Test.Fixtures

  defp insert_cluster!(name, attrs \\ %{}) do
    Fixtures.insert_cluster!(Map.merge(%{name: name}, attrs))
  end

  defp insert_node!(cluster) do
    Fixtures.insert_node!(cluster.id, %{version: "edge-1.0.0"})
  end

  defp insert_alias!(cluster, node, name) do
    Fixtures.insert_alias!(node.id, cluster.id, %{name: name})
  end

  test "combines cluster, node, and name filters while excluding retired clusters" do
    active_cluster = insert_cluster!("prod-east")
    other_cluster = insert_cluster!("staging")
    retired_cluster = insert_cluster!("prod-retired", %{deleted_at: ~U[2026-01-01 00:00:00Z]})

    target_node = insert_node!(active_cluster)
    other_node = insert_node!(other_cluster)
    retired_node = insert_node!(retired_cluster)

    target_alias = insert_alias!(active_cluster, target_node, "edge-api")
    _name_mismatch = insert_alias!(active_cluster, target_node, "db-primary")
    _cluster_mismatch = insert_alias!(other_cluster, other_node, "edge-staging")
    _retired_match = insert_alias!(retired_cluster, retired_node, "edge-retired")

    assert {:ok, {[alias_record], _meta}} =
             AliasResources.list(%{
               "cluster_name" => "prod*",
               "node_id__in" => target_node.id,
               "name" => "edge-*"
             })

    assert alias_record.id == target_alias.id
    assert alias_record.cluster.name == active_cluster.name
  end
end
