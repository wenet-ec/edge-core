# edge_admin/test/edge_admin/nodes/queries/cluster_queries_test.exs
defmodule EdgeAdmin.Nodes.Queries.ClusterQueriesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Test.Fixtures

  defp insert_cluster(overrides \\ %{}), do: Fixtures.insert_cluster!(overrides)
  defp insert_node(cluster_id), do: Fixtures.insert_node!(cluster_id)

  defp ids(query), do: query |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

  describe "active/1" do
    test "returns active clusters and excludes retired clusters" do
      active = insert_cluster()
      retired = insert_cluster(%{deleted_at: ~U[2026-01-01 00:00:00Z]})

      assert ids(ClusterQueries.active()) == [active.id]
      refute retired.id in ids(ClusterQueries.active())
    end
  end

  describe "active_by_name/2 and active_by_id/2" do
    test "match only active clusters" do
      active = insert_cluster()
      retired = insert_cluster(%{deleted_at: ~U[2026-01-01 00:00:00Z]})

      assert ids(ClusterQueries.active_by_name(active.name)) == [active.id]
      assert ids(ClusterQueries.active_by_name(retired.name)) == []
      assert ids(ClusterQueries.active_by_id(active.id)) == [active.id]
      assert ids(ClusterQueries.active_by_id(retired.id)) == []
    end
  end

  describe "active_joined/1" do
    test "filters queries whose cluster is the second binding" do
      active = insert_cluster()
      retired = insert_cluster(%{deleted_at: ~U[2026-01-01 00:00:00Z]})
      active_node = insert_node(active.id)
      retired_node = insert_node(retired.id)

      query =
        from n in Node,
          join: c in assoc(n, :cluster)

      assert ids(ClusterQueries.active_joined(query)) == [active_node.id]
      refute retired_node.id in ids(ClusterQueries.active_joined(query))
    end
  end
end
