# edge_admin/test/edge_admin/nodes/resources/nodes_test.exs
defmodule EdgeAdmin.Nodes.Resources.NodesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.Nodes
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp insert_node do
    cluster =
      Repo.insert!(%Cluster{
        id: Ecto.UUID.generate(),
        name: "cluster-#{System.unique_integer([:positive])}",
        ipv4_range: "100.64.10.0/24",
        ipv6_range: "fd7a:91c2:4e8b:10::/64"
      })

    Repo.insert!(%Node{
      id: Ecto.UUID.generate(),
      cluster_id: cluster.id,
      vpn_host_id: Ecto.UUID.generate(),
      version: "1.0.0",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 49_100,
      wireguard_metrics_port: 49_586,
      http_proxy_port: 43_128,
      socks5_proxy_port: 41_080,
      api_token: Ecto.UUID.generate(),
      proxy_password: Ecto.UUID.generate()
    })
  end

  test "creates, replaces, and deletes the node recovery key" do
    node = insert_node()

    assert {:ok, first_key} = Nodes.create_recovery_key(node)

    assert {:ok, %{"node_id" => node_id, "cluster_name" => cluster_name, "nonce" => nonce}} =
             first_key |> Base.decode64!() |> JSON.decode()

    assert node_id == node.id
    assert cluster_name =~ "cluster-"
    assert is_binary(nonce) and nonce != ""

    node = Repo.get!(Node, node.id)
    assert node.recovery_key == first_key

    assert {:ok, second_key} = Nodes.create_recovery_key(node)
    refute second_key == first_key

    node = Repo.get!(Node, node.id)
    assert {:ok, _} = Nodes.delete_recovery_key(node)
    assert Repo.get!(Node, node.id).recovery_key == nil
  end
end
