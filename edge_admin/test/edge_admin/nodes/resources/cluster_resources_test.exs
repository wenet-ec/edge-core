# edge_admin/test/edge_admin/nodes/resources/cluster_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.ClusterResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.ClusterResources
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Test.Fixtures

  defp insert_cluster!(name, attrs \\ %{}) do
    Fixtures.insert_cluster!(Map.merge(%{name: name}, attrs))
  end

  defp insert_node!(cluster, status) do
    Fixtures.insert_node!(cluster.id, %{status: status, version: "edge-1.0.0"})
  end

  test "lists active cluster-to-node mappings with status and prefix options" do
    mixed = insert_cluster!("mapping-mixed")
    insert_cluster!("mapping-empty")
    unhealthy_only = insert_cluster!("mapping-unhealthy")
    retired = insert_cluster!("mapping-retired", %{deleted_at: ~U[2026-01-01 00:00:00Z]})

    healthy_node = insert_node!(mixed, :healthy)
    _unhealthy_node = insert_node!(mixed, :unhealthy)
    _unhealthy_only_node = insert_node!(unhealthy_only, :unhealthy)
    _retired_node = insert_node!(retired, :healthy)

    mappings = ClusterResources.list_node_mappings(filter_status: [:healthy], prefix: true)
    mappings_by_name = Map.new(mappings, &{&1.name, &1.nodes})
    mapping_names = Enum.sort(Map.keys(mappings_by_name))

    assert mapping_names == ["cluster-mapping-empty", "cluster-mapping-mixed"]

    assert mappings_by_name["cluster-mapping-mixed"] == [Node.node_name(healthy_node)]
    assert mappings_by_name["cluster-mapping-empty"] == []
  end
end
