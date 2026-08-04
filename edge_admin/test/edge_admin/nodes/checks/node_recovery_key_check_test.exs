# edge_admin/test/edge_admin/nodes/checks/node_recovery_key_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.NodeRecoveryKeyCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Checks.NodeRecoveryKeyCheck
  alias EdgeAdmin.Nodes.Schemas.Node

  test "accepts the stored recovery key for its cluster" do
    recovery_key = recovery_key("production")
    node = %Node{recovery_key: recovery_key}

    assert :ok = NodeRecoveryKeyCheck.check(node, recovery_key, "production")
  end

  test "rejects a missing, different, or differently scoped recovery key" do
    recovery_key = recovery_key("production")
    node = %Node{recovery_key: recovery_key}

    assert {:error, :unauthorized} = NodeRecoveryKeyCheck.check(node, nil, "production")
    assert {:error, :unauthorized} = NodeRecoveryKeyCheck.check(node, recovery_key("production-2"), "production")

    differently_scoped_key = recovery_key("staging")

    assert {:error, :unauthorized} =
             NodeRecoveryKeyCheck.check(
               %Node{recovery_key: differently_scoped_key},
               differently_scoped_key,
               "production"
             )
  end

  defp recovery_key(cluster_name) do
    %{"node_id" => "11111111-1111-1111-1111-111111111111", "cluster_name" => cluster_name, "nonce" => "nonce"}
    |> JSON.encode!()
    |> Base.encode64()
  end
end
