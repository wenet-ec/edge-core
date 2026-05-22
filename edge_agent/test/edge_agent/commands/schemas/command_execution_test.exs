# edge_agent/test/edge_agent/commands/schemas/command_execution_test.exs
defmodule EdgeAgent.Commands.Schemas.CommandExecutionTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Commands.Schemas.CommandExecution

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        command_id: Ecto.UUID.generate(),
        node_id: Ecto.UUID.generate(),
        command_text: "uname -a",
        status: "pending"
      },
      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — required fields" do
    test "valid attrs produce a valid changeset" do
      changeset = CommandExecution.changeset(%CommandExecution{}, valid_attrs())
      assert changeset.valid?
    end

    test "id is required" do
      changeset = CommandExecution.changeset(%CommandExecution{}, Map.delete(valid_attrs(), :id))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "command_id is required" do
      changeset =
        CommandExecution.changeset(%CommandExecution{}, Map.delete(valid_attrs(), :command_id))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).command_id
    end

    test "node_id is required" do
      changeset =
        CommandExecution.changeset(%CommandExecution{}, Map.delete(valid_attrs(), :node_id))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).node_id
    end

    test "command_text is required" do
      changeset =
        CommandExecution.changeset(%CommandExecution{}, Map.delete(valid_attrs(), :command_text))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).command_text
    end

    test "status is required" do
      changeset =
        CommandExecution.changeset(%CommandExecution{}, Map.delete(valid_attrs(), :status))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).status
    end

    test "output, exit_code, expires_at, completed_at, timeout are optional" do
      changeset = CommandExecution.changeset(%CommandExecution{}, valid_attrs())
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :output)
      refute Map.has_key?(changeset.changes, :exit_code)
      refute Map.has_key?(changeset.changes, :expires_at)
      refute Map.has_key?(changeset.changes, :completed_at)
    end
  end

  # ---------------------------------------------------------------------------
  # id UUID handling — Uniq.UUID type at the cast layer rejects non-UUID
  # strings; no separate validator needed.
  # ---------------------------------------------------------------------------

  describe "changeset/2 — id UUID handling" do
    test "accepts a valid UUID" do
      changeset =
        CommandExecution.changeset(
          %CommandExecution{},
          valid_attrs(%{id: "01234567-89ab-cdef-0123-456789abcdef"})
        )

      assert changeset.valid?
    end

    test "rejects a malformed UUID at the cast layer" do
      changeset =
        CommandExecution.changeset(%CommandExecution{}, valid_attrs(%{id: "not-a-uuid"}))

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).id
    end

    test "rejects an empty string" do
      changeset = CommandExecution.changeset(%CommandExecution{}, valid_attrs(%{id: ""}))
      refute changeset.valid?

      # cast drops empty string to nil → validate_required fires "can't be blank".
      assert "can't be blank" in errors_on(changeset).id
    end
  end

  # ---------------------------------------------------------------------------
  # Status inclusion
  # ---------------------------------------------------------------------------

  describe "changeset/2 — status inclusion" do
    test "accepts the three documented statuses" do
      for status <- ["pending", "completed", "expired"] do
        changeset =
          CommandExecution.changeset(%CommandExecution{}, valid_attrs(%{status: status}))

        assert changeset.valid?, "expected status #{inspect(status)} to be valid"
      end
    end

    test "rejects anything else" do
      for status <- ["sent", "cancelled", "PENDING", "in_progress", "failed"] do
        changeset =
          CommandExecution.changeset(%CommandExecution{}, valid_attrs(%{status: status}))

        refute changeset.valid?, "expected status #{inspect(status)} to be rejected"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cast allowlist
  # ---------------------------------------------------------------------------

  describe "changeset/2 — cast allowlist" do
    test "ignores unknown fields" do
      changeset =
        CommandExecution.changeset(%CommandExecution{}, valid_attrs(%{not_a_field: "leak"}))

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :not_a_field)
    end
  end
end
