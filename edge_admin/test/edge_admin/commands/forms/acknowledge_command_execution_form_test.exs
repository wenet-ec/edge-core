# edge_admin/test/edge_admin/commands/forms/acknowledge_command_execution_form_test.exs
defmodule EdgeAdmin.Commands.Forms.AcknowledgeCommandExecutionFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Forms.AcknowledgeCommandExecutionForm

  # ---------------------------------------------------------------------------
  # changeset/2 — acknowledgeable status
  # ---------------------------------------------------------------------------

  describe "changeset/2 — pending status" do
    test "pending execution can be acknowledged with empty attrs" do
      assert {:ok, %{}} = AcknowledgeCommandExecutionForm.changeset(%{}, "pending")
    end

    test "pending execution can be acknowledged with extra attrs ignored" do
      assert {:ok, %{}} = AcknowledgeCommandExecutionForm.changeset(%{"foo" => "bar"}, "pending")
    end

    test "pending execution with wrapped params unwraps and succeeds" do
      attrs = %{"command_execution" => %{"some_field" => "ignored"}}
      assert {:ok, %{}} = AcknowledgeCommandExecutionForm.changeset(attrs, "pending")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — non-acknowledgeable statuses
  # ---------------------------------------------------------------------------

  describe "changeset/2 — non-pending status" do
    test "sent execution cannot be acknowledged" do
      assert {:error, changeset} = AcknowledgeCommandExecutionForm.changeset(%{}, "sent")
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "sent"
      assert msg =~ "pending"
    end

    test "completed execution cannot be acknowledged" do
      assert {:error, changeset} = AcknowledgeCommandExecutionForm.changeset(%{}, "completed")
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "completed"
      assert msg =~ "pending"
    end

    test "unknown status cannot be acknowledged" do
      assert {:error, changeset} = AcknowledgeCommandExecutionForm.changeset(%{}, "other")
      assert %{base: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/2 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        AcknowledgeCommandExecutionForm.changeset("not_a_map", "pending")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        AcknowledgeCommandExecutionForm.changeset(nil, "pending")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
