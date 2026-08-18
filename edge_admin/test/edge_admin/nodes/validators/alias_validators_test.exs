# edge_admin/test/edge_admin/nodes/validators/alias_validators_test.exs
defmodule EdgeAdmin.Nodes.Validators.AliasValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Validators.AliasValidators

  test "accepts valid alias names" do
    assert AliasValidators.valid_name?("web-1")
  end

  test "rejects invalid alias names" do
    refute AliasValidators.valid_name?("")
    refute AliasValidators.valid_name?("bad name")
    refute AliasValidators.valid_name?(nil)
  end
end
