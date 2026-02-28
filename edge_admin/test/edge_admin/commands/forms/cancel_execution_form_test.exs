# edge_admin/test/edge_admin/commands/forms/cancel_execution_form_test.exs
defmodule EdgeAdmin.Commands.Forms.CancelExecutionFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Forms.CancelExecutionForm

  # ---------------------------------------------------------------------------
  # changeset/1 — cancellable statuses
  # ---------------------------------------------------------------------------

  describe "changeset/1 — cancellable statuses" do
    test "pending execution can be cancelled" do
      assert {:ok, %{}} = CancelExecutionForm.changeset("pending")
    end

    test "sent execution can be cancelled" do
      assert {:ok, %{}} = CancelExecutionForm.changeset("sent")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — non-cancellable statuses
  # ---------------------------------------------------------------------------

  describe "changeset/1 — non-cancellable statuses" do
    test "completed execution cannot be cancelled" do
      assert {:error, changeset} = CancelExecutionForm.changeset("completed")
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "completed"
      assert msg =~ "pending"
      assert msg =~ "sent"
    end

    test "unknown status cannot be cancelled" do
      assert {:error, changeset} = CancelExecutionForm.changeset("unknown_status")
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "unknown_status"
    end

    test "empty string status cannot be cancelled" do
      assert {:error, changeset} = CancelExecutionForm.changeset("")
      assert %{status: [_msg]} = errors_on(changeset)
    end

    test "error message mentions both valid statuses" do
      {:error, changeset} = CancelExecutionForm.changeset("completed")
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "pending"
      assert msg =~ "sent"
    end
  end

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
