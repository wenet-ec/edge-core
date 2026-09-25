# edge_admin/test/edge_admin/commands/checks/command_execution_finalized_check_test.exs
defmodule EdgeAdmin.Commands.Checks.CommandExecutionFinalizedCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Checks.CommandExecutionFinalizedCheck
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @admin_completed_at ~U[2026-09-25 00:00:00Z]
  # check/1
  #
  # Pure function: checks finalization fields on the struct, no DB call.

  describe "check/1 — finalized executions" do
    test "completed execution returns :ok" do
      execution = %CommandExecution{status: :completed}
      assert :ok = CommandExecutionFinalizedCheck.check(execution)
    end

    test "cancelled execution returns :ok" do
      execution = %CommandExecution{status: :cancelled, completed_at: @admin_completed_at}
      assert :ok = CommandExecutionFinalizedCheck.check(execution)
    end

    test "expired execution returns :ok" do
      execution = %CommandExecution{status: :expired, completed_at: @admin_completed_at}
      assert :ok = CommandExecutionFinalizedCheck.check(execution)
    end

    test "dropped execution returns :ok" do
      execution = %CommandExecution{status: :dropped}
      assert :ok = CommandExecutionFinalizedCheck.check(execution)
    end
  end

  describe "check/1 — executions that are not finalized" do
    test "pending execution returns conflict error" do
      execution = %CommandExecution{status: :pending}
      assert {:error, {:conflict, reason}} = CommandExecutionFinalizedCheck.check(execution)
      assert reason =~ "pending"
      assert reason =~ "finalized"
    end

    test "sent execution returns conflict error" do
      execution = %CommandExecution{status: :sent}
      assert {:error, {:conflict, reason}} = CommandExecutionFinalizedCheck.check(execution)
      assert reason =~ "sent"
      assert reason =~ "finalized"
    end

    test "cancelled execution awaiting an Agent result returns conflict" do
      execution = %CommandExecution{status: :cancelled, completed_at: nil}
      assert {:error, {:conflict, reason}} = CommandExecutionFinalizedCheck.check(execution)
      assert reason =~ "finalized"
    end

    test "expired execution awaiting an Agent result returns conflict" do
      execution = %CommandExecution{status: :expired, completed_at: nil}
      assert {:error, {:conflict, reason}} = CommandExecutionFinalizedCheck.check(execution)
      assert reason =~ "finalized"
    end

    test "error message includes the actual status" do
      execution = %CommandExecution{status: :pending}
      {:error, {:conflict, reason}} = CommandExecutionFinalizedCheck.check(execution)
      assert reason =~ "pending"
    end
  end
end
