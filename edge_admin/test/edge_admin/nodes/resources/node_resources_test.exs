# edge_admin/test/edge_admin/nodes/resources/node_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.NodeResourcesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Resources.NodeResources

  test "builds a recovery key containing the node and cluster binding" do
    node_id = "node-id"
    cluster_name = "production"
    nonce = "fixed-nonce"

    key = NodeResources.build_recovery_key(node_id, cluster_name, nonce)

    assert {:ok, json} = Base.decode64(key)
    assert {:ok, %{"node_id" => ^node_id, "cluster_name" => ^cluster_name, "nonce" => ^nonce}} = JSON.decode(json)
  end
end
