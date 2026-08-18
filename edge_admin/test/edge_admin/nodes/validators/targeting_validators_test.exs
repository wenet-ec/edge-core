# edge_admin/test/edge_admin/nodes/validators/targeting_validators_test.exs
defmodule EdgeAdmin.Nodes.Validators.TargetingValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Validators.TargetingValidators

  test "accepts all targeting types" do
    assert TargetingValidators.valid_type?("all")
    assert TargetingValidators.valid_type?("nodes")
    assert TargetingValidators.valid_type?("clusters")
    refute TargetingValidators.valid_type?("specific")
  end

  test "enforces conditional target lists" do
    assert TargetingValidators.requirement_error("all", nil, nil) == :ok
    assert {:error, :node_ids, _} = TargetingValidators.requirement_error("nodes", [], nil)
    assert {:error, :cluster_names, _} = TargetingValidators.requirement_error("clusters", nil, [])
    assert TargetingValidators.requirement_error("nodes", ["id"], nil) == :ok
  end

  test "validates a complete targeting map" do
    assert TargetingValidators.errors(%{"type" => "all"}) == []
    assert TargetingValidators.errors(%{"type" => "nodes"}) != []
    assert TargetingValidators.errors(%{"type" => "unknown"}) != []
  end
end
