# edge_admin/test/edge_admin/nodes/filters/cluster_filters_test.exs
defmodule EdgeAdmin.Nodes.Filters.ClusterFiltersTest do
  # async: false because DataCase shares the sandbox in non-async mode and
  # filter behaviour depends on which rows happen to exist.
  use EdgeAdmin.DataCase, async: false

  import Ecto.Query

  alias EdgeAdmin.Nodes.Filters.ClusterFilters
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  # Unique fixture identifiers per VM. `:erlang.unique_integer([:positive, :monotonic])`
  # never repeats within a process, eliminating the birthday-paradox flake we got with
  # `:rand.uniform/1` on small ranges like `/24` over `100.64.X.0`.
  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])

  # Walks the 16_384 `/24` blocks inside CGNAT (`100.64.0.0/10`):
  #   second octet ∈ 64..127, third octet ∈ 0..255.
  defp unique_ipv4_range do
    n = unique_id()
    octet2 = 64 + rem(div(n, 256), 64)
    octet3 = rem(n, 256)
    "100.#{octet2}.#{octet3}.0/24"
  end

  defp insert_cluster(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          name: "cluster-#{unique_id()}",
          ipv4_range: unique_ipv4_range(),
          node_limit: nil
        },
        overrides
      )

    Repo.insert!(struct(Cluster, attrs))
  end

  defp insert_node(cluster_id) do
    attrs = %{
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
    }

    Repo.insert!(struct(Node, attrs))
  end

  # Returns the IDs of clusters yielded by a query, sorted, so tests don't
  # depend on result ordering.
  defp ids(query), do: query |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

  defp aggregate_query do
    from(c in Cluster,
      left_join: n in assoc(c, :nodes),
      group_by: c.id,
      select_merge: %{node_count: count(n.id)}
    )
  end

  # ---------------------------------------------------------------------------
  # apply_has_node_limit/2 — virtual boolean: node_limit IS [NOT] NULL
  # ---------------------------------------------------------------------------

  describe "apply_has_node_limit/2" do
    test "true matches clusters with a non-null node_limit" do
      with_limit = insert_cluster(%{node_limit: 50})
      _without_limit = insert_cluster(%{node_limit: nil})

      query = ClusterFilters.apply_has_node_limit(Cluster, [%{op: :==, value: true}])

      assert ids(query) == [with_limit.id]
    end

    test "false matches clusters with a null node_limit" do
      _with_limit = insert_cluster(%{node_limit: 50})
      without_limit = insert_cluster(%{node_limit: nil})

      query = ClusterFilters.apply_has_node_limit(Cluster, [%{op: :==, value: false}])

      assert ids(query) == [without_limit.id]
    end

    test "string 'true' / 'false' values work the same way" do
      with_limit = insert_cluster(%{node_limit: 50})
      without_limit = insert_cluster(%{node_limit: nil})

      assert ids(ClusterFilters.apply_has_node_limit(Cluster, [%{op: :==, value: "true"}])) ==
               [with_limit.id]

      assert ids(ClusterFilters.apply_has_node_limit(Cluster, [%{op: :==, value: "false"}])) ==
               [without_limit.id]
    end

    test "no filters → query unchanged" do
      a = insert_cluster()
      b = insert_cluster()

      query = ClusterFilters.apply_has_node_limit(Cluster, [])

      assert ids(query) == Enum.sort([a.id, b.id])
    end

    test "unrecognised filter shape is ignored (catch-all)" do
      a = insert_cluster()
      b = insert_cluster()

      query =
        ClusterFilters.apply_has_node_limit(Cluster, [%{op: :>, value: 5}])

      assert ids(query) == Enum.sort([a.id, b.id])
    end
  end

  # ---------------------------------------------------------------------------
  # apply_ilike/2 — bypasses Flop's add_wildcard so user-supplied % patterns
  # work as written.
  # ---------------------------------------------------------------------------

  describe "apply_ilike/2" do
    test "matches by case-insensitive LIKE on the named field" do
      prod = insert_cluster(%{name: "prod-east"})
      _staging = insert_cluster(%{name: "staging-east"})

      query =
        ClusterFilters.apply_ilike(Cluster, [%{field: :name, op: :ilike, value: "PROD%"}])

      assert ids(query) == [prod.id]
    end

    test "user-supplied % is honoured (not escaped — that's the whole point)" do
      _a = insert_cluster(%{name: "abc-1"})
      ab = insert_cluster(%{name: "abc-2"})
      _c = insert_cluster(%{name: "xyz-1"})

      # "abc%" should match anything starting with "abc".
      query =
        ClusterFilters.apply_ilike(Cluster, [%{field: :name, op: :ilike, value: "abc%"}])

      ids = ids(query)
      assert ab.id in ids
      assert length(ids) == 2
    end

    test "multiple ilike filters compose with AND" do
      # ipv4_range has a unique index, so each cluster needs a distinct subnet.
      # Pin name + range filters such that only the target satisfies both.
      target = insert_cluster(%{name: "prod-east-1", ipv4_range: "10.1.1.0/24"})
      _wrong_name = insert_cluster(%{name: "staging-east", ipv4_range: "10.1.2.0/24"})
      _wrong_range = insert_cluster(%{name: "prod-west", ipv4_range: "10.2.0.0/24"})

      query =
        ClusterFilters.apply_ilike(Cluster, [
          %{field: :name, op: :ilike, value: "prod%"},
          %{field: :ipv4_range, op: :ilike, value: "10.1.%"}
        ])

      assert ids(query) == [target.id]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_node_count/2 — HAVING clause over count(nodes.id). Caller must
  # left-join nodes and group by cluster id (see aggregate_query/0).
  # ---------------------------------------------------------------------------

  describe "apply_node_count/2 (>=, >, <=, <, ==, !=)" do
    setup do
      # Pin distinct IP ranges so the unique index on ipv4_range can't bite
      # us (random rolls collide ~3% of the time across 4 clusters).
      empty = insert_cluster(%{ipv4_range: "10.10.0.0/24"})
      one = insert_cluster(%{ipv4_range: "10.10.1.0/24"})
      two = insert_cluster(%{ipv4_range: "10.10.2.0/24"})
      five = insert_cluster(%{ipv4_range: "10.10.3.0/24"})

      insert_node(one.id)

      Enum.each(1..2, fn _ -> insert_node(two.id) end)
      Enum.each(1..5, fn _ -> insert_node(five.id) end)

      %{empty: empty, one: one, two: two, five: five}
    end

    test ">= integer", %{one: one, two: two, five: five} do
      query = ClusterFilters.apply_node_count(aggregate_query(), [%{op: :>=, value: 1}])
      assert ids(query) == Enum.sort([one.id, two.id, five.id])
    end

    test ">= binary (Integer.parse handles string inputs)", %{two: two, five: five} do
      query = ClusterFilters.apply_node_count(aggregate_query(), [%{op: :>=, value: "2"}])
      assert ids(query) == Enum.sort([two.id, five.id])
    end

    test "> integer", %{two: two, five: five} do
      query = ClusterFilters.apply_node_count(aggregate_query(), [%{op: :>, value: 1}])
      assert ids(query) == Enum.sort([two.id, five.id])
    end

    test "<= integer", %{empty: empty, one: one, two: two} do
      query = ClusterFilters.apply_node_count(aggregate_query(), [%{op: :<=, value: 2}])
      assert ids(query) == Enum.sort([empty.id, one.id, two.id])
    end

    test "< integer", %{empty: empty, one: one} do
      query = ClusterFilters.apply_node_count(aggregate_query(), [%{op: :<, value: 2}])
      assert ids(query) == Enum.sort([empty.id, one.id])
    end

    test "== integer", %{five: five} do
      query = ClusterFilters.apply_node_count(aggregate_query(), [%{op: :==, value: 5}])
      assert ids(query) == [five.id]
    end

    test "!= integer", %{empty: empty, one: one, five: five} do
      # !=2 → exclude `two`. Keep `empty`, `one`, `five`.
      query = ClusterFilters.apply_node_count(aggregate_query(), [%{op: :!=, value: 2}])
      assert ids(query) == Enum.sort([empty.id, one.id, five.id])
    end

    test "non-integer string → filter is silently dropped" do
      query = ClusterFilters.apply_node_count(aggregate_query(), [%{op: :>=, value: "abc"}])

      # Filter dropped means we get every cluster from the aggregate query.
      assert length(Repo.all(query)) == 4
    end

    test "no filters → query unchanged" do
      query = ClusterFilters.apply_node_count(aggregate_query(), [])
      assert length(Repo.all(query)) == 4
    end
  end

  # ---------------------------------------------------------------------------
  # apply_name/2 — filters on the SECOND binding (cluster joined onto a
  # primary table). Used by node/alias/enrollment-key listings that join
  # cluster for filtering.
  # ---------------------------------------------------------------------------

  describe "apply_name/2 (operates on second binding)" do
    test "== matches by exact cluster name" do
      cluster_a = insert_cluster(%{name: "alpha"})
      cluster_b = insert_cluster(%{name: "bravo"})

      node_a = insert_node(cluster_a.id)
      _node_b = insert_node(cluster_b.id)

      base = from(n in Node, join: c in assoc(n, :cluster), select: n)

      query = ClusterFilters.apply_name(base, [%{op: :==, value: "alpha"}])

      assert query |> Repo.all() |> Enum.map(& &1.id) == [node_a.id]
    end

    test "ilike matches by wildcard cluster name" do
      cluster_prod = insert_cluster(%{name: "prod-east"})
      cluster_staging = insert_cluster(%{name: "staging-east"})

      node_prod = insert_node(cluster_prod.id)
      _node_staging = insert_node(cluster_staging.id)

      base = from(n in Node, join: c in assoc(n, :cluster), select: n)

      query = ClusterFilters.apply_name(base, [%{field: :name, op: :ilike, value: "PROD%"}])

      assert query |> Repo.all() |> Enum.map(& &1.id) == [node_prod.id]
    end

    test "no filters → query unchanged" do
      cluster_a = insert_cluster()
      cluster_b = insert_cluster()
      _node_a = insert_node(cluster_a.id)
      _node_b = insert_node(cluster_b.id)

      base = from(n in Node, join: c in assoc(n, :cluster), select: n)

      assert base |> ClusterFilters.apply_name([]) |> Repo.all() |> length() == 2
    end
  end
end
