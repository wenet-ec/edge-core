# edge_admin/test/edge_admin/commands/forms/update_command_execution_result_form_test.exs
defmodule EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultForm

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid cases" do
    test "succeeds with output and exit_code" do
      attrs = %{"output" => "hello", "exit_code" => 0}
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["output"] == "hello"
      assert result["exit_code"] == 0
    end

    test "succeeds with empty attrs" do
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{})
      assert Map.has_key?(result, "completed_at")
    end

    test "unwraps command_execution key automatically" do
      attrs = %{"command_execution" => %{"output" => "hi", "exit_code" => 1}}
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["output"] == "hi"
      assert result["exit_code"] == 1
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — completed_at handling
  # ---------------------------------------------------------------------------

  describe "changeset/1 — completed_at field" do
    test "defaults completed_at to now when not provided" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{})
      assert %DateTime{} = result["completed_at"]
    end

    test "accepts a valid ISO8601 datetime string" do
      attrs = %{"completed_at" => "2024-01-15T10:30:00Z"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert %DateTime{year: 2024, month: 1, day: 15} = result["completed_at"]
    end

    test "accepts a DateTime struct directly" do
      dt = ~U[2024-06-01 12:00:00Z]
      attrs = %{"completed_at" => dt}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["completed_at"] == dt
    end

    test "completed_at is truncated to second precision" do
      attrs = %{"completed_at" => "2024-01-15T10:30:00.123456Z"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["completed_at"].microsecond == {0, 0}
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output structure
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "nil output is excluded from result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{})
      refute Map.has_key?(result, "output")
    end

    test "nil exit_code is excluded from result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{})
      refute Map.has_key?(result, "exit_code")
    end

    test "present output is included in result map" do
      attrs = %{"output" => "done"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["output"] == "done"
    end

    test "exit_code 0 is included in result map" do
      attrs = %{"exit_code" => 0}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["exit_code"] == 0
    end

    test "completed_at is always present in result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{})
      assert Map.has_key?(result, "completed_at")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        UpdateCommandExecutionResultForm.changeset("bad")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        UpdateCommandExecutionResultForm.changeset(nil)
      end
    end
  end
end
