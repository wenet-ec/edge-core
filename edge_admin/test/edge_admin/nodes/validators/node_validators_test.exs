# edge_admin/test/edge_admin/nodes/validators/node_validators_test.exs
defmodule EdgeAdmin.Nodes.Validators.NodeValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Validators.NodeValidators

  describe "valid_port?/1" do
    test "accepts the inclusive port range" do
      assert NodeValidators.valid_port?(1)
      assert NodeValidators.valid_port?(65_535)
    end

    test "rejects values outside the range or with the wrong type" do
      refute NodeValidators.valid_port?(0)
      refute NodeValidators.valid_port?(65_536)
      refute NodeValidators.valid_port?(-1)
      refute NodeValidators.valid_port?("8080")
      refute NodeValidators.valid_port?(nil)
    end
  end

  describe "valid_network_name?/1" do
    test "requires the cluster prefix" do
      assert NodeValidators.valid_network_name?("cluster-edge")
      refute NodeValidators.valid_network_name?("edge")
      refute NodeValidators.valid_network_name?(nil)
    end
  end
end
