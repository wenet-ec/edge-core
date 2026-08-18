# edge_agent/test/edge_agent/commands/validators/command_execution_validators_test.exs
defmodule EdgeAgent.Commands.Validators.CommandExecutionValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Commands.Validators.CommandExecutionValidators

  describe "valid_command_text?/1" do
    test "accepts nonblank command text" do
      assert CommandExecutionValidators.valid_command_text?("uptime")
      assert CommandExecutionValidators.valid_command_text?("  uptime  ")
    end

    test "rejects blank and non-string values" do
      refute CommandExecutionValidators.valid_command_text?(" \t\n")
      refute CommandExecutionValidators.valid_command_text?(nil)
      refute CommandExecutionValidators.valid_command_text?(123)
    end
  end

  describe "valid_timeout?/1" do
    test "allows nil and positive integers" do
      assert CommandExecutionValidators.valid_timeout?(nil)
      assert CommandExecutionValidators.valid_timeout?(1)
    end

    test "rejects zero, negative, and non-integer values" do
      refute CommandExecutionValidators.valid_timeout?(0)
      refute CommandExecutionValidators.valid_timeout?(-1)
      refute CommandExecutionValidators.valid_timeout?("1000")
    end
  end
end
