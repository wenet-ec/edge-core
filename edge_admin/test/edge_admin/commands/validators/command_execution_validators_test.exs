# edge_admin/test/edge_admin/commands/validators/command_execution_validators_test.exs
defmodule EdgeAdmin.Commands.Validators.CommandExecutionValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Validators.CommandExecutionValidators

  test "accepts nil, DateTime, and valid ISO8601 timestamps" do
    assert CommandExecutionValidators.valid_completed_at?(nil)
    assert CommandExecutionValidators.valid_completed_at?(~U[2026-01-01 00:00:00Z])
    assert CommandExecutionValidators.valid_completed_at?("2026-01-01T00:00:00Z")
  end

  test "rejects malformed timestamps" do
    refute CommandExecutionValidators.valid_completed_at?("not-a-date")
    refute CommandExecutionValidators.valid_completed_at?(123)
  end
end
