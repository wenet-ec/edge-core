defmodule EdgeAdmin.Commands.Rules.DeletionRulesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Rules.DeletionRules
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  # ---------------------------------------------------------------------------
  # validate_execution_deletion/1
  #
  # Pure function: pattern matches on the struct's :status field, no DB call.
  # ---------------------------------------------------------------------------

  describe "validate_execution_deletion/1 — completed execution" do
    test "completed execution returns :ok" do
      execution = %CommandExecution{status: "completed"}
      assert :ok = DeletionRules.validate_execution_deletion(execution)
    end
  end

  describe "validate_execution_deletion/1 — non-completed executions" do
    test "pending execution cannot be deleted" do
      execution = %CommandExecution{status: "pending"}
      assert {:error, changeset} = DeletionRules.validate_execution_deletion(execution)
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "pending"
      assert msg =~ "completed"
    end

    test "sent execution cannot be deleted" do
      execution = %CommandExecution{status: "sent"}
      assert {:error, changeset} = DeletionRules.validate_execution_deletion(execution)
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "sent"
      assert msg =~ "completed"
    end

    test "error message includes the actual status" do
      execution = %CommandExecution{status: "pending"}
      {:error, changeset} = DeletionRules.validate_execution_deletion(execution)
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "pending"
    end
  end

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
