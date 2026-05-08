# edge_admin/test/edge_admin/commands/checks/execution_cancellable_check_test.exs
defmodule EdgeAdmin.Commands.Checks.ExecutionCancellableCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Checks.ExecutionCancellableCheck
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  # ---------------------------------------------------------------------------
  # check/1 — pure struct pattern match, no DB
  # ---------------------------------------------------------------------------

  describe "check/1 — cancellable statuses" do
    test "pending execution returns :ok" do
      execution = %CommandExecution{status: :pending}
      assert :ok = ExecutionCancellableCheck.check(execution)
    end

    test "sent execution returns :ok" do
      execution = %CommandExecution{status: :sent}
      assert :ok = ExecutionCancellableCheck.check(execution)
    end
  end

  describe "check/1 — non-cancellable statuses" do
    test "completed execution returns conflict error" do
      execution = %CommandExecution{status: :completed}
      assert {:error, {:conflict, reason}} = ExecutionCancellableCheck.check(execution)
      assert reason =~ "completed"
      assert reason =~ "pending"
      assert reason =~ "sent"
    end

    test "cancelled execution returns conflict error" do
      execution = %CommandExecution{status: :cancelled}
      assert {:error, {:conflict, reason}} = ExecutionCancellableCheck.check(execution)
      assert reason =~ "cancelled"
      assert reason =~ "pending"
      assert reason =~ "sent"
    end

    test "expired execution returns conflict error" do
      execution = %CommandExecution{status: :expired}
      assert {:error, {:conflict, reason}} = ExecutionCancellableCheck.check(execution)
      assert reason =~ "expired"
      assert reason =~ "pending"
      assert reason =~ "sent"
    end

    test "unknown status returns conflict error" do
      execution = %CommandExecution{status: :unknown_status}
      assert {:error, {:conflict, reason}} = ExecutionCancellableCheck.check(execution)
      assert reason =~ "unknown_status"
    end

    test "error message mentions both valid statuses" do
      execution = %CommandExecution{status: :completed}
      {:error, {:conflict, reason}} = ExecutionCancellableCheck.check(execution)
      assert reason =~ "pending"
      assert reason =~ "sent"
    end
  end
end
