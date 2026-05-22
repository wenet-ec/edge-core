# edge_agent/test/edge_agent/commands/forms/create_command_execution_form_test.exs
defmodule EdgeAgent.Commands.Forms.CreateCommandExecutionFormTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Commands.Forms.CreateCommandExecutionForm

  @valid_id "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  @valid_command_id "11111111-2222-3333-4444-555555555555"
  @valid_node_id "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb"

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => @valid_id,
        "command_id" => @valid_command_id,
        "node_id" => @valid_node_id,
        "command_text" => "uptime",
        "status" => "pending"
      },
      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # -----------------------------------------------------------------------
  # Happy path
  # -----------------------------------------------------------------------

  describe "changeset/1 — valid inputs" do
    test "returns {:ok, map} for minimal valid attrs" do
      assert {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      assert is_map(result)
    end

    test "result has string keys" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      assert Map.has_key?(result, "id")
      assert Map.has_key?(result, "command_id")
      assert Map.has_key?(result, "node_id")
      assert Map.has_key?(result, "command_text")
      assert Map.has_key?(result, "status")
    end

    test "required field values are preserved in result (status cast to atom)" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      assert result["id"] == @valid_id
      assert result["command_id"] == @valid_command_id
      assert result["node_id"] == @valid_node_id
      assert result["command_text"] == "uptime"
      assert result["status"] == :pending
    end

    test "status: completed is accepted (cast to atom)" do
      assert {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs(%{"status" => "completed"}))
      assert result["status"] == :completed
    end

    test "status: expired is accepted (cast to atom)" do
      assert {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs(%{"status" => "expired"}))
      assert result["status"] == :expired
    end

    test "expires_at is accepted when present" do
      future = ~U[2099-01-01 00:00:00Z]
      assert {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs(%{"expires_at" => future}))
      assert result["expires_at"] == future
    end

    test "nil expires_at is excluded from result" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      refute Map.has_key?(result, "expires_at")
    end

    test "timeout: positive integer is accepted" do
      assert {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs(%{"timeout" => 30_000}))
      assert result["timeout"] == 30_000
    end

    test "timeout: boundary value 1 is accepted" do
      assert {:ok, _} = CreateCommandExecutionForm.changeset(valid_attrs(%{"timeout" => 1}))
    end

    test "optional output is included in result when present" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs(%{"output" => "some output"}))
      assert result["output"] == "some output"
    end

    test "optional exit_code is included in result when present" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs(%{"exit_code" => 0}))
      assert result["exit_code"] == 0
    end

    test "optional completed_at is included in result when present as ISO8601 string" do
      {:ok, result} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"completed_at" => "2026-01-01T10:00:00Z"}))

      assert %DateTime{} = result["completed_at"]
    end

    test "wrapped params with atom keys are also accepted" do
      attrs = %{
        id: @valid_id,
        command_id: @valid_command_id,
        node_id: @valid_node_id,
        command_text: "ls",
        status: "pending"
      }

      assert {:ok, _} = CreateCommandExecutionForm.changeset(attrs)
    end
  end

  # -----------------------------------------------------------------------
  # to_map — nil exclusion
  # -----------------------------------------------------------------------

  describe "changeset/1 — to_map nil exclusion" do
    test "nil timeout is excluded from result" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      refute Map.has_key?(result, "timeout")
    end

    test "nil output is excluded from result" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      refute Map.has_key?(result, "output")
    end

    test "nil exit_code is excluded from result" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      refute Map.has_key?(result, "exit_code")
    end

    test "nil completed_at is excluded from result" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      refute Map.has_key?(result, "completed_at")
    end

    test "nil expires_at is excluded from result" do
      {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      refute Map.has_key?(result, "expires_at")
    end

    test "all optional fields present when provided" do
      attrs =
        valid_attrs(%{
          "timeout" => 5000,
          "expires_at" => ~U[2099-01-01 00:00:00Z],
          "output" => "ok",
          "exit_code" => 0,
          "completed_at" => "2026-01-01T10:00:00Z"
        })

      {:ok, result} = CreateCommandExecutionForm.changeset(attrs)
      assert Map.has_key?(result, "timeout")
      assert Map.has_key?(result, "expires_at")
      assert Map.has_key?(result, "output")
      assert Map.has_key?(result, "exit_code")
      assert Map.has_key?(result, "completed_at")
    end
  end

  # -----------------------------------------------------------------------
  # Required fields
  # -----------------------------------------------------------------------

  describe "changeset/1 — required fields" do
    for field <- ["id", "command_id", "node_id", "command_text", "status"] do
      test "missing #{field} returns error" do
        attrs = Map.delete(valid_attrs(), unquote(field))
        assert {:error, changeset} = CreateCommandExecutionForm.changeset(attrs)
        assert Map.has_key?(errors_on(changeset), String.to_existing_atom(unquote(field)))
      end
    end
  end

  # -----------------------------------------------------------------------
  # UUID validation
  # -----------------------------------------------------------------------

  describe "changeset/1 — UUID format validation" do
    test "non-UUID id is rejected" do
      {:error, changeset} = CreateCommandExecutionForm.changeset(valid_attrs(%{"id" => "not-a-uuid"}))
      assert hd(errors_on(changeset).id) =~ "UUID"
    end

    test "non-UUID command_id is rejected" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"command_id" => "not-a-uuid"}))

      assert hd(errors_on(changeset).command_id) =~ "UUID"
    end

    test "non-UUID node_id is rejected" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"node_id" => "not-a-uuid"}))

      assert hd(errors_on(changeset).node_id) =~ "UUID"
    end

    test "empty string id is rejected" do
      {:error, changeset} = CreateCommandExecutionForm.changeset(valid_attrs(%{"id" => ""}))
      assert Map.has_key?(errors_on(changeset), :id)
    end
  end

  # -----------------------------------------------------------------------
  # command_text validation
  # -----------------------------------------------------------------------

  describe "changeset/1 — command_text validation" do
    test "whitespace-only command_text is rejected (validate_required trims, treats as blank)" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"command_text" => "   "}))

      assert Map.has_key?(errors_on(changeset), :command_text)
    end

    test "tab-only command_text is rejected (validate_required trims, treats as blank)" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"command_text" => "\t\t"}))

      assert Map.has_key?(errors_on(changeset), :command_text)
    end

    test "empty string command_text is rejected as required" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"command_text" => ""}))

      assert Map.has_key?(errors_on(changeset), :command_text)
    end

    test "command_text with leading/trailing spaces is accepted" do
      assert {:ok, result} =
               CreateCommandExecutionForm.changeset(valid_attrs(%{"command_text" => "  uptime  "}))

      assert result["command_text"] == "  uptime  "
    end
  end

  # -----------------------------------------------------------------------
  # status validation
  # -----------------------------------------------------------------------

  describe "changeset/1 — status validation" do
    test "invalid status is rejected" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"status" => "running"}))

      assert Map.has_key?(errors_on(changeset), :status)
    end

    test "uppercase status is rejected" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"status" => "Pending"}))

      assert Map.has_key?(errors_on(changeset), :status)
    end

    test "empty status is rejected" do
      {:error, changeset} = CreateCommandExecutionForm.changeset(valid_attrs(%{"status" => ""}))
      assert Map.has_key?(errors_on(changeset), :status)
    end

    test "sent status is rejected (admin-only status)" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"status" => "sent"}))

      assert Map.has_key?(errors_on(changeset), :status)
    end

    test "cancelled status is rejected (agent uses expired or completed)" do
      {:error, changeset} =
        CreateCommandExecutionForm.changeset(valid_attrs(%{"status" => "cancelled"}))

      assert Map.has_key?(errors_on(changeset), :status)
    end
  end

  # -----------------------------------------------------------------------
  # timeout validation
  # -----------------------------------------------------------------------

  describe "changeset/1 — timeout validation" do
    test "zero timeout is rejected" do
      {:error, changeset} = CreateCommandExecutionForm.changeset(valid_attrs(%{"timeout" => 0}))
      assert hd(errors_on(changeset).timeout) =~ "positive"
    end

    test "negative timeout is rejected" do
      {:error, changeset} = CreateCommandExecutionForm.changeset(valid_attrs(%{"timeout" => -1}))
      assert hd(errors_on(changeset).timeout) =~ "positive"
    end

    test "nil timeout is allowed (field omitted from result)" do
      assert {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs(%{"timeout" => nil}))
      refute Map.has_key?(result, "timeout")
    end

    test "absent timeout is allowed" do
      assert {:ok, result} = CreateCommandExecutionForm.changeset(valid_attrs())
      refute Map.has_key?(result, "timeout")
    end
  end

  # -----------------------------------------------------------------------
  # Non-map params
  # -----------------------------------------------------------------------

  describe "changeset/1 — non-map params" do
    test "string params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} = CreateCommandExecutionForm.changeset("not a map")
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end

    test "nil params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} = CreateCommandExecutionForm.changeset(nil)
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end

    test "list params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} = CreateCommandExecutionForm.changeset([1, 2, 3])
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end
  end
end
