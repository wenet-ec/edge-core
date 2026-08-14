# edge_agent/test/edge_agent/commands/enums/command_execution_statuses_test.exs
defmodule EdgeAgent.Commands.Enums.CommandExecutionStatusesTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Commands.Enums.CommandExecutionStatuses

  describe "statuses/0" do
    test "returns local lifecycle statuses in canonical order" do
      assert CommandExecutionStatuses.statuses() == [:pending, :running, :completed, :expired]
    end
  end

  describe "incoming_statuses/0" do
    test "accepts only pending executions from Admin" do
      assert CommandExecutionStatuses.incoming_statuses() == [:pending]
    end
  end

  describe "recoverable_statuses/0" do
    test "returns statuses that should be enqueued for execution" do
      assert CommandExecutionStatuses.recoverable_statuses() == [:pending, :running]
    end
  end

  describe "status_strings/0" do
    test "returns wire strings in canonical order" do
      assert CommandExecutionStatuses.status_strings() == ["pending", "running", "completed", "expired"]
    end
  end

  describe "incoming_status_strings/0" do
    test "returns incoming wire strings in canonical order" do
      assert CommandExecutionStatuses.incoming_status_strings() == ["pending"]
    end
  end
end
