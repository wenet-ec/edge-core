# edge_admin/test/edge_admin/commands/validators/command_validators_test.exs
defmodule EdgeAdmin.Commands.Validators.CommandValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Validators.CommandValidators

  test "validates command text" do
    assert CommandValidators.valid_command_text?("  uname -a  ")
    refute CommandValidators.valid_command_text?("  \n")
  end

  test "validates optional positive timeouts" do
    assert CommandValidators.valid_timeout?(nil)
    assert CommandValidators.valid_timeout?(1)
    refute CommandValidators.valid_timeout?(0)
    refute CommandValidators.valid_timeout?("1000")
  end

  test "validates expiry against an explicit clock" do
    now = ~U[2026-01-01 00:00:00Z]
    assert CommandValidators.valid_expiry?(~U[2026-01-01 00:00:01Z], now)
    assert CommandValidators.valid_expiry?(nil, now)
    refute CommandValidators.valid_expiry?(now, now)
  end
end
