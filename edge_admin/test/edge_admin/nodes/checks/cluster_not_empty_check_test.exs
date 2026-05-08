# edge_admin/test/edge_admin/nodes/checks/cluster_not_empty_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.ClusterNotEmptyCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Checks.ClusterNotEmptyCheck
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp insert_cluster do
    attrs = %{
      id: Ecto.UUID.generate(),
      name: "cluster-#{:rand.uniform(999_999)}",
      ipv4_range: "100.64.#{:rand.uniform(200)}.0/24"
    }

    Repo.insert!(struct(Cluster, attrs))
  end

  defp insert_node(cluster_id) do
    attrs = %{
      id: Ecto.UUID.generate(),
      cluster_id: cluster_id,
      id_type: :persistent,
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
    }

    Repo.insert!(struct(Node, attrs))
  end

  # ---------------------------------------------------------------------------
  # check/1 — empty cluster
  # ---------------------------------------------------------------------------

  describe "check/1 — empty cluster" do
    test "cluster with no nodes returns :ok" do
      cluster = insert_cluster()
      assert :ok = ClusterNotEmptyCheck.check(cluster)
    end
  end

  # ---------------------------------------------------------------------------
  # check/1 — cluster with nodes
  # ---------------------------------------------------------------------------

  describe "check/1 — cluster with nodes" do
    test "cluster with one node returns conflict error" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = ClusterNotEmptyCheck.check(cluster)
      assert reason =~ "1"
    end

    test "cluster with multiple nodes returns conflict error with count" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      insert_node(cluster.id)
      insert_node(cluster.id)
      assert {:error, {:conflict, reason}} = ClusterNotEmptyCheck.check(cluster)
      assert reason =~ "3"
    end

    test "error message instructs to remove nodes first" do
      cluster = insert_cluster()
      insert_node(cluster.id)
      {:error, {:conflict, reason}} = ClusterNotEmptyCheck.check(cluster)
      assert reason =~ "remove"
    end
  end
end
