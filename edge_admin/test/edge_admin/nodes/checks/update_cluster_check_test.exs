# edge_admin/test/edge_admin/nodes/checks/update_cluster_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.UpdateClusterCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Checks.UpdateClusterCheck
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp insert_cluster(overrides \\ %{}) do
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
  # check/2 — nil new_limit
  # ---------------------------------------------------------------------------

  describe "check/2 — nil new_limit (removing the cap)" do
    test "nil new_limit always returns :ok regardless of node count" do
      cluster = insert_cluster()
      assert :ok = UpdateClusterCheck.check(cluster, nil)
    end

    test "nil new_limit returns :ok even when cluster has nodes" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert :ok = UpdateClusterCheck.check(cluster, nil)
    end
  end

  # ---------------------------------------------------------------------------
  # check/2 — new_limit >= node count
  # ---------------------------------------------------------------------------

  describe "check/2 — new_limit accommodates existing nodes" do
    test "new_limit equal to node count returns :ok" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert :ok = UpdateClusterCheck.check(cluster, 2)
    end

    test "new_limit greater than node count returns :ok" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      assert :ok = UpdateClusterCheck.check(cluster, 5)
    end

    test "empty cluster with any positive limit returns :ok" do
      cluster = insert_cluster()
      assert :ok = UpdateClusterCheck.check(cluster, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # check/2 — new_limit < node count
  # ---------------------------------------------------------------------------

  describe "check/2 — new_limit below current node count" do
    test "new_limit below node count returns conflict error" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = UpdateClusterCheck.check(cluster, 1)
      assert is_binary(reason)
    end

    test "error message includes the proposed limit" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      {:error, {:conflict, reason}} = UpdateClusterCheck.check(cluster, 1)
      assert reason =~ "1"
    end

    test "error message includes the current node count" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      {:error, {:conflict, reason}} = UpdateClusterCheck.check(cluster, 1)
      assert reason =~ "2"
    end

    test "zero new_limit is always below a non-empty cluster" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      assert {:error, {:conflict, _reason}} = UpdateClusterCheck.check(cluster, 0)
    end
  end
end
