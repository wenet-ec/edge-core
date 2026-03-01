# edge_admin/test/edge_admin/commands/checks/acknowledge_execution_check_test.exs
defmodule EdgeAdmin.Commands.Checks.AcknowledgeExecutionCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Checks.AcknowledgeExecutionCheck
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  # ---------------------------------------------------------------------------
  # check/1 — pure struct pattern match, no DB
  # ---------------------------------------------------------------------------

  describe "check/1 — pending execution" do
    test "pending execution returns :ok" do
      execution = %CommandExecution{status: "pending"}
      assert :ok = AcknowledgeExecutionCheck.check(execution)
    end
  end

  describe "check/1 — non-pending executions" do
    test "sent execution returns conflict error" do
      execution = %CommandExecution{status: "sent"}
      assert {:error, {:conflict, reason}} = AcknowledgeExecutionCheck.check(execution)
      assert reason =~ "sent"
      assert reason =~ "pending"
    end

    test "completed execution returns conflict error" do
      execution = %CommandExecution{status: "completed"}
      assert {:error, {:conflict, reason}} = AcknowledgeExecutionCheck.check(execution)
      assert reason =~ "completed"
      assert reason =~ "pending"
    end

    test "error message includes the actual status" do
      execution = %CommandExecution{status: "sent"}
      {:error, {:conflict, reason}} = AcknowledgeExecutionCheck.check(execution)
      assert reason =~ "sent"
    end
  end
end
