# edge_admin/test/edge_admin/commands/forms/update_command_execution_result_form_test.exs
defmodule EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultForm

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid cases" do
    test "succeeds with status completed, output and exit_code" do
      attrs = %{"status" => "completed", "output" => "hello", "exit_code" => 0}
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["status"] == "completed"
      assert result["output"] == "hello"
      assert result["exit_code"] == 0
    end

    test "succeeds with status expired and no output or exit_code" do
      attrs = %{"status" => "expired"}
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["status"] == "expired"
    end

    test "unwraps command_execution key automatically" do
      attrs = %{command_execution: %{status: "completed", output: "hi", exit_code: 1}}
      assert {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["status"] == "completed"
      assert result["output"] == "hi"
      assert result["exit_code"] == 1
    end

    test "status is required — missing status returns error" do
      assert {:error, changeset} = UpdateCommandExecutionResultForm.changeset(%{})
      assert %{status: [_msg]} = errors_on(changeset)
    end

    test "invalid status is rejected" do
      attrs = %{"status" => "running"}
      assert {:error, changeset} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert %{status: [_msg]} = errors_on(changeset)
    end

    test "status is included in result map" do
      attrs = %{"status" => "completed"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["status"] == "completed"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — completed_at handling
  # ---------------------------------------------------------------------------

  describe "changeset/1 — completed_at field" do
    test "defaults completed_at to now when not provided" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{"status" => "completed"})
      assert %DateTime{} = result["completed_at"]
    end

    test "accepts a valid ISO8601 datetime string" do
      attrs = %{"status" => "completed", "completed_at" => "2024-01-15T10:30:00Z"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert %DateTime{year: 2024, month: 1, day: 15} = result["completed_at"]
    end

    test "accepts a DateTime struct directly" do
      dt = ~U[2024-06-01 12:00:00Z]
      attrs = %{"status" => "completed", "completed_at" => dt}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["completed_at"] == dt
    end

    test "completed_at is truncated to second precision" do
      attrs = %{"status" => "completed", "completed_at" => "2024-01-15T10:30:00.123456Z"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["completed_at"].microsecond == {0, 0}
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output structure
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "nil output is excluded from result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{"status" => "completed"})
      refute Map.has_key?(result, "output")
    end

    test "nil exit_code is excluded from result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{"status" => "completed"})
      refute Map.has_key?(result, "exit_code")
    end

    test "present output is included in result map" do
      attrs = %{"status" => "completed", "output" => "done"}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["output"] == "done"
    end

    test "exit_code 0 is included in result map" do
      attrs = %{"status" => "completed", "exit_code" => 0}
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(attrs)
      assert result["exit_code"] == 0
    end

    test "completed_at is always present in result map" do
      {:ok, result} = UpdateCommandExecutionResultForm.changeset(%{"status" => "completed"})
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
