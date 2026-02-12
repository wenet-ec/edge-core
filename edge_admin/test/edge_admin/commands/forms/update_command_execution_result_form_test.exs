defmodule EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultForm

  # ---------------------------------------------------------------------------
  # changeset/3 — valid status transitions
  # ---------------------------------------------------------------------------

  describe "changeset/3 — valid status transitions" do
    test "sent execution can be updated" do
      attrs = %{"output" => "hello", "exit_code" => 0}
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs, "sent", nil)
      assert result["output"] == "hello"
      assert result["exit_code"] == 0
    end

    test "sent execution with no output or exit_code succeeds" do
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{}, "sent", nil)
      assert Map.has_key?(result, "completed_at")
    end

    test "completed execution with exit_code 143 can be overwritten (cancelled race condition)" do
      attrs = %{"output" => "actual result", "exit_code" => 0}
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs, "completed", 143)
      assert result["output"] == "actual result"
      assert result["exit_code"] == 0
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/3 — invalid status transitions
  # ---------------------------------------------------------------------------

  describe "changeset/3 — invalid status transitions" do
    test "pending execution cannot be updated" do
      assert {:error, changeset} =
               UpdateCommandExecutionResultForm.changeset(%{}, "pending", nil)

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "pending"
    end

    test "completed execution with non-143 exit_code cannot be updated" do
      assert {:error, changeset} =
               UpdateCommandExecutionResultForm.changeset(%{}, "completed", 0)

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "completed"
    end

    test "completed execution with nil exit_code cannot be updated" do
      assert {:error, changeset} =
               UpdateCommandExecutionResultForm.changeset(%{}, "completed", nil)

      assert %{base: [_msg]} = errors_on(changeset)
    end

    test "unknown status cannot be updated" do
      assert {:error, changeset} =
               UpdateCommandExecutionResultForm.changeset(%{}, "unknown", nil)

      assert %{base: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/3 — completed_at handling
  # ---------------------------------------------------------------------------

  describe "changeset/3 — completed_at field" do
    test "defaults completed_at to now when not provided" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{}, "sent", nil)
      assert %DateTime{} = result["completed_at"]
    end

    test "accepts a valid ISO8601 datetime string" do
      attrs = %{"completed_at" => "2024-01-15T10:30:00Z"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs, "sent", nil)
      assert %DateTime{year: 2024, month: 1, day: 15} = result["completed_at"]
    end

    test "accepts a DateTime struct directly" do
      dt = ~U[2024-06-01 12:00:00Z]
      attrs = %{"completed_at" => dt}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs, "sent", nil)
      assert result["completed_at"] == dt
    end

    test "completed_at is truncated to second precision" do
      attrs = %{"completed_at" => "2024-01-15T10:30:00.123456Z"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs, "sent", nil)
      assert result["completed_at"].microsecond == {0, 0}
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/3 — to_map output structure
  # ---------------------------------------------------------------------------

  describe "changeset/3 — to_map output" do
    test "nil output is excluded from result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{}, "sent", nil)
      refute Map.has_key?(result, "output")
    end

    test "nil exit_code is excluded from result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{}, "sent", nil)
      refute Map.has_key?(result, "exit_code")
    end

    test "present output is included in result map" do
      attrs = %{"output" => "done"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs, "sent", nil)
      assert result["output"] == "done"
    end

    test "exit_code 0 is included in result map" do
      attrs = %{"exit_code" => 0}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs, "sent", nil)
      assert result["exit_code"] == 0
    end

    test "completed_at is always present in result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{}, "sent", nil)
      assert Map.has_key?(result, "completed_at")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/3 — wrapped params
  # ---------------------------------------------------------------------------

  describe "changeset/3 — wrapped params" do
    test "unwraps command_execution key automatically" do
      attrs = %{"command_execution" => %{"output" => "hi", "exit_code" => 1}}
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs, "sent", nil)
      assert result["output"] == "hi"
      assert result["exit_code"] == 1
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/3 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/3 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        UpdateCommandExecutionResultForm.changeset("bad", "sent", nil)
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
