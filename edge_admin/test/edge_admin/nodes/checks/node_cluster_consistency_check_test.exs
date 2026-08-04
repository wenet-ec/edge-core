# edge_admin/test/edge_admin/nodes/checks/node_cluster_consistency_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.NodeClusterConsistencyCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Checks.NodeClusterConsistencyCheck
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp insert_cluster(id, name, octet) do
    Repo.insert!(%Cluster{
      id: id,
      name: name,
      ipv4_range: "100.64.#{octet}.0/24",
      ipv6_range: "fd7a:91c2:4e8b:#{octet}::/64"
    })
  end

  defp insert_node(id, cluster_id) do
    Repo.insert!(%Node{
      id: id,
      cluster_id: cluster_id,
      netmaker_host_id: Ecto.UUID.generate(),
      status: :healthy,
      version: "0.1.0",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9_100,
      wireguard_metrics_port: 9_586,
      http_proxy_port: 8_080,
      socks5_proxy_port: 10_080,
      api_token: Ecto.UUID.generate(),
      proxy_password: Ecto.UUID.generate()
    })
  end

  test "accepts an alias whose cluster matches the node cluster" do
    cluster = insert_cluster(Ecto.UUID.generate(), "cluster-match", 1)
    node = insert_node(Ecto.UUID.generate(), cluster.id)

    changeset = Alias.changeset(%Alias{}, %{name: "web", node_id: node.id, cluster_id: cluster.id})

    assert {:ok, ^changeset} = NodeClusterConsistencyCheck.check(changeset)
  end

  test "rejects an alias whose cluster differs from the node cluster" do
    node_cluster = insert_cluster(Ecto.UUID.generate(), "cluster-node", 2)
    other_cluster = insert_cluster(Ecto.UUID.generate(), "cluster-other", 3)
    node = insert_node(Ecto.UUID.generate(), node_cluster.id)

    changeset =
      Alias.changeset(%Alias{}, %{name: "web", node_id: node.id, cluster_id: other_cluster.id})

    assert {:error, changeset} = NodeClusterConsistencyCheck.check(changeset)
    assert "must match the node's cluster" in errors_on(changeset).cluster_id
  end
end
