# edge_admin/test/edge_admin/commands/schemas/command_test.exs
defmodule EdgeAdmin.Commands.Schemas.CommandTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Schemas.Command

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        command_text: "uname -a",
        targeting: %{"type" => "all"},
        timeout: 30_000
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
      changeset = Command.changeset(%Command{}, valid_attrs())
      assert changeset.valid?
    end

    test "command_text is required" do
      changeset = Command.changeset(%Command{}, Map.delete(valid_attrs(), :command_text))
      refute changeset.valid?
      assert %{command_text: ["can't be blank"]} = errors_on(changeset)
    end

    test "targeting is required" do
      changeset = Command.changeset(%Command{}, Map.delete(valid_attrs(), :targeting))
      refute changeset.valid?
      assert %{targeting: ["can't be blank"]} = errors_on(changeset)
    end

    test "timeout is optional" do
      changeset = Command.changeset(%Command{}, Map.delete(valid_attrs(), :timeout))
      assert changeset.valid?
    end

    test "expired_at is optional" do
      changeset = Command.changeset(%Command{}, valid_attrs())
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :expired_at)
    end
  end

  # ---------------------------------------------------------------------------
  # validate_command_text_format
  # ---------------------------------------------------------------------------

  describe "changeset/2 — command_text blank handling" do
    # validate_required/3 trims strings before checking blankness, so empty,
    # whitespace-only, and newline-only inputs all surface as "can't be blank".
    # No dedicated whitespace validator is needed — validate_required covers it.

    test "rejects empty string" do
      changeset = Command.changeset(%Command{}, valid_attrs(%{command_text: ""}))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).command_text
    end

    test "rejects whitespace-only" do
      changeset = Command.changeset(%Command{}, valid_attrs(%{command_text: "   "}))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).command_text
    end

    test "rejects newline-only" do
      changeset = Command.changeset(%Command{}, valid_attrs(%{command_text: "\n\t  \n"}))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).command_text
    end

    test "accepts text with leading/trailing whitespace (preserved verbatim)" do
      changeset = Command.changeset(%Command{}, valid_attrs(%{command_text: "  ls  "}))
      assert changeset.valid?
      # The original (untrimmed) value is preserved — caller can decide whether
      # to trim before passing in.
      assert Ecto.Changeset.get_change(changeset, :command_text) == "  ls  "
    end
  end

  # ---------------------------------------------------------------------------
  # validate_timeout
  # ---------------------------------------------------------------------------

  describe "changeset/2 — timeout" do
    test "nil timeout is valid (optional field)" do
      changeset = Command.changeset(%Command{}, valid_attrs(%{timeout: nil}))
      assert changeset.valid?
    end

    test "positive integer is valid" do
      changeset = Command.changeset(%Command{}, valid_attrs(%{timeout: 60_000}))
      assert changeset.valid?
    end

    test "zero is rejected" do
      changeset = Command.changeset(%Command{}, valid_attrs(%{timeout: 0}))
      refute changeset.valid?

      assert "must be a positive number (in milliseconds)" in errors_on(changeset).timeout
    end

    test "negative timeout is rejected" do
      changeset = Command.changeset(%Command{}, valid_attrs(%{timeout: -1}))
      refute changeset.valid?

      assert "must be a positive number (in milliseconds)" in errors_on(changeset).timeout
    end
  end

  # ---------------------------------------------------------------------------
  # validate_expired_at
  # ---------------------------------------------------------------------------

  describe "changeset/2 — expired_at" do
    test "future timestamp is valid" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      changeset = Command.changeset(%Command{}, valid_attrs(%{expired_at: future}))
      assert changeset.valid?
    end

    test "past timestamp is rejected" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      changeset = Command.changeset(%Command{}, valid_attrs(%{expired_at: past}))
      refute changeset.valid?

      assert "must be in the future" in errors_on(changeset).expired_at
    end

    test "current time (or essentially now) is rejected (DateTime.after? is strict)" do
      # The cast truncates to :utc_datetime (second precision), so 'now' as
      # given is at best equal to the comparison's now, never strictly after.
      now = DateTime.truncate(DateTime.utc_now(), :second)
      changeset = Command.changeset(%Command{}, valid_attrs(%{expired_at: now}))
      refute changeset.valid?
    end
  end
end
