# edge_admin/test/edge_admin/nodes/checks/node_limit_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.NodeLimitCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Checks.NodeLimitCheck
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp insert_cluster(overrides) do
    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          name: "cluster-#{:rand.uniform(999_999)}",
          ipv4_range: "100.64.#{:rand.uniform(200)}.0/24"
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

  # ---------------------------------------------------------------------------
  # check/1 — no limit
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # check/1 — with limit, below limit
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # check/1 — at or above limit
  # ---------------------------------------------------------------------------

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
