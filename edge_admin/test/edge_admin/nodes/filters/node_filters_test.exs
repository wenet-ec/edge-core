# edge_admin/test/edge_admin/nodes/filters/node_filters_test.exs
defmodule EdgeAdmin.Nodes.Filters.NodeFiltersTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Filters.NodeFilters
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp insert_cluster do
    Repo.insert!(
      struct(Cluster, %{
        id: Ecto.UUID.generate(),
        name: "cluster-#{:rand.uniform(999_999)}",
        ipv4_range: "100.64.#{:rand.uniform(200)}.0/24"
      })
    )
  end

  defp insert_node(cluster_id, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          cluster_id: cluster_id,
          id_type: "persistent",
          status: "healthy",
          version: "0.1.0",
          http_port: 44_000,
          ssh_port: 40_022,
          host_metrics_port: 9100,
          wireguard_metrics_port: 9586,
          http_proxy_port: 8080,
          socks5_proxy_port: 1080,
          api_token: Ecto.UUID.generate(),
          proxy_password: Ecto.UUID.generate()
        },
        overrides
      )

    Repo.insert!(struct(Node, attrs))
  end

  defp ids(query), do: query |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

  # ---------------------------------------------------------------------------
  # apply_ilike/2
  # ---------------------------------------------------------------------------

  describe "apply_ilike/2" do
    test "matches by case-insensitive LIKE on a string field (version)" do
      cluster = insert_cluster()
      v_010 = insert_node(cluster.id, %{version: "0.1.0"})
      _v_020 = insert_node(cluster.id, %{version: "0.2.0"})

      query =
        NodeFilters.apply_ilike(Node, [%{field: :version, op: :ilike, value: "0.1%"}])

      assert ids(query) == [v_010.id]
    end

    test "user-supplied % is honoured (not double-wrapped)" do
      cluster = insert_cluster()
      a = insert_node(cluster.id, %{version: "1.0.0"})
      b = insert_node(cluster.id, %{version: "1.0.1"})
      _c = insert_node(cluster.id, %{version: "2.0.0"})

      # Caller writes "1.0%" — they expect prefix match. Flop's :ilike would
      # have wrapped this as %1.0\%% and broken the semantics; this filter
      # passes the value through.
      query =
        NodeFilters.apply_ilike(Node, [%{field: :version, op: :ilike, value: "1.0%"}])

      assert ids(query) == Enum.sort([a.id, b.id])
    end

    test "match is case-insensitive (the whole reason this helper exists)" do
      cluster = insert_cluster()
      n = insert_node(cluster.id, %{version: "Edge-1.0"})

      query =
        NodeFilters.apply_ilike(Node, [%{field: :version, op: :ilike, value: "edge%"}])

      assert ids(query) == [n.id]
    end

    test "multiple ilike filters AND together" do
      cluster = insert_cluster()
      target = insert_node(cluster.id, %{version: "0.1.0", id_type: "persistent"})
      _wrong_version = insert_node(cluster.id, %{version: "0.2.0", id_type: "persistent"})
      _wrong_type = insert_node(cluster.id, %{version: "0.1.0", id_type: "random"})

      query =
        NodeFilters.apply_ilike(Node, [
          %{field: :version, op: :ilike, value: "0.1%"},
          %{field: :id_type, op: :ilike, value: "persistent"}
        ])

      assert ids(query) == [target.id]
    end

    test "no filters → query unchanged" do
      cluster = insert_cluster()
      a = insert_node(cluster.id)
      b = insert_node(cluster.id)

      assert ids(NodeFilters.apply_ilike(Node, [])) == Enum.sort([a.id, b.id])
    end
  end
end
