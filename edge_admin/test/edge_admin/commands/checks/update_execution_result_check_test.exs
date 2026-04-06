# edge_admin/test/edge_admin/commands/checks/update_execution_result_check_test.exs
defmodule EdgeAdmin.Commands.Checks.UpdateExecutionResultCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Checks.UpdateExecutionResultCheck
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  # ---------------------------------------------------------------------------
  # check/1 — pure struct pattern match, no DB
  # ---------------------------------------------------------------------------

  describe "check/1 — updatable executions" do
    test "sent execution returns :ok" do
      execution = %CommandExecution{status: "sent", exit_code: nil}
      assert :ok = UpdateExecutionResultCheck.check(execution)
    end

    test "cancelled execution with nil exit_code returns :ok (race: admin cancelled, agent already ran)" do
      execution = %CommandExecution{status: "cancelled", exit_code: nil}
      assert :ok = UpdateExecutionResultCheck.check(execution)
    end

    test "expired execution with nil exit_code returns :ok (race: admin expired, agent already ran)" do
      execution = %CommandExecution{status: "expired", exit_code: nil}
      assert :ok = UpdateExecutionResultCheck.check(execution)
    end
  end

  describe "check/1 — non-updatable executions" do
    test "pending execution returns conflict error" do
      execution = %CommandExecution{status: "pending", exit_code: nil}
      assert {:error, {:conflict, reason}} = UpdateExecutionResultCheck.check(execution)
      assert reason =~ "pending"
    end

    test "completed execution with exit_code 0 returns conflict error" do
      execution = %CommandExecution{status: "completed", exit_code: 0}
      assert {:error, {:conflict, reason}} = UpdateExecutionResultCheck.check(execution)
      assert reason =~ "completed"
    end

    test "completed execution with nil exit_code returns conflict error" do
      execution = %CommandExecution{status: "completed", exit_code: nil}
      assert {:error, {:conflict, reason}} = UpdateExecutionResultCheck.check(execution)
      assert reason =~ "completed"
    end

    test "cancelled execution with non-nil exit_code returns conflict error (already terminal)" do
      execution = %CommandExecution{status: "cancelled", exit_code: 143}
      assert {:error, {:conflict, reason}} = UpdateExecutionResultCheck.check(execution)
      assert reason =~ "cancelled"
    end

    test "expired execution with non-nil exit_code returns conflict error (already terminal)" do
      execution = %CommandExecution{status: "expired", exit_code: 0}
      assert {:error, {:conflict, reason}} = UpdateExecutionResultCheck.check(execution)
      assert reason =~ "expired"
    end

    test "error message includes the actual status and exit_code" do
      execution = %CommandExecution{status: "pending", exit_code: nil}
      {:error, {:conflict, reason}} = UpdateExecutionResultCheck.check(execution)
      assert reason =~ "pending"
    end
  end
end
