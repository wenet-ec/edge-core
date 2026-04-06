# edge_admin/test/edge_admin/commands/checks/delete_execution_check_test.exs
defmodule EdgeAdmin.Commands.Checks.DeleteExecutionCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Checks.DeleteExecutionCheck
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  # ---------------------------------------------------------------------------
  # check/1
  #
  # Pure function: pattern matches on the struct's :status field, no DB call.
  # ---------------------------------------------------------------------------

  describe "check/1 — terminal executions" do
    test "completed execution returns :ok" do
      execution = %CommandExecution{status: "completed"}
      assert :ok = DeleteExecutionCheck.check(execution)
    end

    test "cancelled execution returns :ok" do
      execution = %CommandExecution{status: "cancelled"}
      assert :ok = DeleteExecutionCheck.check(execution)
    end

    test "expired execution returns :ok" do
      execution = %CommandExecution{status: "expired"}
      assert :ok = DeleteExecutionCheck.check(execution)
    end
  end

  describe "check/1 — non-terminal executions" do
    test "pending execution returns conflict error" do
      execution = %CommandExecution{status: "pending"}
      assert {:error, {:conflict, reason}} = DeleteExecutionCheck.check(execution)
      assert reason =~ "pending"
      assert reason =~ "completed"
    end

    test "sent execution returns conflict error" do
      execution = %CommandExecution{status: "sent"}
      assert {:error, {:conflict, reason}} = DeleteExecutionCheck.check(execution)
      assert reason =~ "sent"
      assert reason =~ "completed"
    end

    test "error message includes the actual status" do
      execution = %CommandExecution{status: "pending"}
      {:error, {:conflict, reason}} = DeleteExecutionCheck.check(execution)
      assert reason =~ "pending"
    end
  end
end
