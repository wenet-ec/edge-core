# edge_admin/test/edge_admin/commands/filters/execution_filters_test.exs
defmodule EdgeAdmin.Commands.Filters.ExecutionFiltersTest do
  use EdgeAdmin.DataCase, async: false

  import Ecto.Query

  alias EdgeAdmin.Commands.Filters.ExecutionFilters
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp insert_cluster(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          name: "cluster-#{unique_id()}",
          ipv4_range: unique_ipv4_range()
        },
        overrides
      )

    Repo.insert!(struct(Cluster, attrs))
  end

  # See cluster_filters_test for rationale: monotonic ints, not random, so
  # birthday-paradox collisions on the small `100.64.X.0/24` space disappear.
  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])

  defp unique_ipv4_range do
    n = unique_id()
    octet2 = 64 + rem(div(n, 256), 64)
    octet3 = rem(n, 256)
    "100.#{octet2}.#{octet3}.0/24"
  end

  defp insert_node(cluster_id) do
    Repo.insert!(
      struct(Node, %{
        id: Ecto.UUID.generate(),
        cluster_id: cluster_id,
        id_type: "persistent",
        status: :healthy,
        version: "0.1.0",
        http_port: 44_000,
        ssh_port: 40_022,
        host_metrics_port: 9100,
        wireguard_metrics_port: 9586,
        http_proxy_port: 8080,
        socks5_proxy_port: 1080,
        api_token: Ecto.UUID.generate(),
        proxy_password: Ecto.UUID.generate()
      })
    )
  end

  defp insert_command do
    Repo.insert!(
      struct(Command, %{
        id: Ecto.UUID.generate(),
        command_text: "echo hello",
        targeting: %{}
      })
    )
  end

  defp insert_execution(node_id, opts \\ []) do
    cluster_id = Keyword.get(opts, :cluster_id, nil)
    output = Keyword.get(opts, :output, nil)
    command_id = Keyword.get(opts, :command_id, insert_command().id)

    # Use Ecto.Changeset.change/2 to write nil cluster_id / output explicitly
    # (struct insert + nil with no schema default is fine for these fields,
    # but using change/2 keeps the pattern uniform with the EnrollmentKey
    # filters test where it actually matters).
    %CommandExecution{}
    |> Ecto.Changeset.change(%{
      id: Ecto.UUID.generate(),
      command_id: command_id,
      node_id: node_id,
      cluster_id: cluster_id,
      status: :pending,
      output: output
    })
    |> Repo.insert!()
  end

  # Base query mirroring list_command_executions/1's join shape:
  # `[ce, n, c]` — execution joined to its node and the node's cluster.
  defp base_query do
    from(ce in CommandExecution,
      join: n in assoc(ce, :node),
      join: c in assoc(n, :cluster),
      select: ce
    )
  end

  defp ids(query), do: query |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

  # ---------------------------------------------------------------------------
  # apply_cluster_name/2 — filters by the node's cluster name (3rd binding)
  # ---------------------------------------------------------------------------

  describe "apply_cluster_name/2" do
    test "== matches by exact node-cluster name" do
      cluster_a = insert_cluster(%{name: "alpha"})
      cluster_b = insert_cluster(%{name: "bravo"})

      node_a = insert_node(cluster_a.id)
      node_b = insert_node(cluster_b.id)

      exec_a = insert_execution(node_a.id)
      _exec_b = insert_execution(node_b.id)

      query = ExecutionFilters.apply_cluster_name(base_query(), [%{op: :==, value: "alpha"}])

      assert ids(query) == [exec_a.id]
    end

    test "ilike matches by wildcard pattern, case-insensitively" do
      cluster_prod = insert_cluster(%{name: "prod-east"})
      cluster_staging = insert_cluster(%{name: "staging-east"})

      node_prod = insert_node(cluster_prod.id)
      node_staging = insert_node(cluster_staging.id)

      exec_prod = insert_execution(node_prod.id)
      _exec_staging = insert_execution(node_staging.id)

      query =
        ExecutionFilters.apply_cluster_name(base_query(), [
          %{field: :cluster_name, op: :ilike, value: "PROD%"}
        ])

      assert ids(query) == [exec_prod.id]
    end

    test "no filters → query unchanged" do
      cluster_a = insert_cluster()
      cluster_b = insert_cluster()
      node_a = insert_node(cluster_a.id)
      node_b = insert_node(cluster_b.id)

      a = insert_execution(node_a.id)
      b = insert_execution(node_b.id)

      assert ids(ExecutionFilters.apply_cluster_name(base_query(), [])) ==
               Enum.sort([a.id, b.id])
    end

    test "unrecognised filter op is silently dropped (catch-all)" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)
      exec_a = insert_execution(node_a.id)

      query = ExecutionFilters.apply_cluster_name(base_query(), [%{op: :>=, value: 5}])

      # Filter ignored → all executions visible.
      assert ids(query) == [exec_a.id]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_has_cluster/2 — checks ce.cluster_id (the execution's OWN cluster
  # column, NOT the node's cluster — these can differ for target_all
  # executions where cluster_id is nil despite the node belonging to a
  # cluster).
  # ---------------------------------------------------------------------------

  describe "apply_has_cluster/2" do
    test "true matches executions whose own cluster_id is non-null" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)

      with_cluster = insert_execution(node_a.id, cluster_id: cluster_a.id)
      _without_cluster = insert_execution(node_a.id, cluster_id: nil)

      query = ExecutionFilters.apply_has_cluster(base_query(), [%{op: :==, value: true}])

      assert ids(query) == [with_cluster.id]
    end

    test "false matches executions whose own cluster_id is nil" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)

      _with_cluster = insert_execution(node_a.id, cluster_id: cluster_a.id)
      without_cluster = insert_execution(node_a.id, cluster_id: nil)

      query = ExecutionFilters.apply_has_cluster(base_query(), [%{op: :==, value: false}])

      assert ids(query) == [without_cluster.id]
    end

    test "string 'true' / 'false' both work" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)

      with_cluster = insert_execution(node_a.id, cluster_id: cluster_a.id)
      without_cluster = insert_execution(node_a.id, cluster_id: nil)

      assert ids(ExecutionFilters.apply_has_cluster(base_query(), [%{op: :==, value: "true"}])) ==
               [with_cluster.id]

      assert ids(ExecutionFilters.apply_has_cluster(base_query(), [%{op: :==, value: "false"}])) ==
               [without_cluster.id]
    end

    test "no filters → query unchanged" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)
      a = insert_execution(node_a.id)
      b = insert_execution(node_a.id)

      assert ids(ExecutionFilters.apply_has_cluster(base_query(), [])) ==
               Enum.sort([a.id, b.id])
    end
  end

  # ---------------------------------------------------------------------------
  # apply_has_output/2 — output IS [NOT] NULL (no binding constraint —
  # operates on the primary CommandExecution binding)
  # ---------------------------------------------------------------------------

  describe "apply_has_output/2" do
    test "true matches executions whose output is non-null" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)

      with_output = insert_execution(node_a.id, output: "hello\n")
      _without_output = insert_execution(node_a.id, output: nil)

      query = ExecutionFilters.apply_has_output(base_query(), [%{op: :==, value: true}])

      assert ids(query) == [with_output.id]
    end

    test "false matches executions whose output is nil" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)

      _with_output = insert_execution(node_a.id, output: "hello\n")
      without_output = insert_execution(node_a.id, output: nil)

      query = ExecutionFilters.apply_has_output(base_query(), [%{op: :==, value: false}])

      assert ids(query) == [without_output.id]
    end

    test "empty-string output is treated as 'has output' (NOT NULL is the rule)" do
      # Documents actual SQL semantics: NOT NULL is NULL-vs-not-NULL only.
      # An empty-string output is a real value and counts as 'has output'.
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)
      empty = insert_execution(node_a.id, output: "")

      query = ExecutionFilters.apply_has_output(base_query(), [%{op: :==, value: true}])
      assert ids(query) == [empty.id]
    end

    test "no filters → query unchanged" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)
      a = insert_execution(node_a.id)
      b = insert_execution(node_a.id)

      assert ids(ExecutionFilters.apply_has_output(base_query(), [])) ==
               Enum.sort([a.id, b.id])
    end
  end
end
