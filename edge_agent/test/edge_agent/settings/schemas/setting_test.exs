# edge_agent/test/edge_agent/settings/schemas/setting_test.exs
defmodule EdgeAgent.Settings.Schemas.SettingTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Settings.Schemas.Setting

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{key: "node_id", value: "abc-123"}, overrides)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end

  describe "changeset/2 — required fields" do
    test "valid attrs produce a valid changeset" do
      changeset = Setting.changeset(%Setting{}, valid_attrs())
      assert changeset.valid?
    end

    test "key is required" do
      changeset = Setting.changeset(%Setting{}, Map.delete(valid_attrs(), :key))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).key
    end

    test "value is required" do
      changeset = Setting.changeset(%Setting{}, Map.delete(valid_attrs(), :value))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).value
    end

    test "empty string value is rejected (cast drops to nil → required fires)" do
      changeset = Setting.changeset(%Setting{}, valid_attrs(%{value: ""}))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).value
    end
  end

  describe "changeset/2 — key length bounds" do
    test "1-character key is accepted" do
      changeset = Setting.changeset(%Setting{}, valid_attrs(%{key: "a"}))
      assert changeset.valid?
    end

    test "255-character key is accepted (boundary)" do
      changeset = Setting.changeset(%Setting{}, valid_attrs(%{key: String.duplicate("a", 255)}))
      assert changeset.valid?
    end

    test "256-character key is rejected" do
      changeset = Setting.changeset(%Setting{}, valid_attrs(%{key: String.duplicate("a", 256)}))
      refute changeset.valid?
      assert Enum.any?(errors_on(changeset).key, &String.contains?(&1, "255"))
    end

    test "empty key is rejected (validate_required catches it; length check is skipped on nil)" do
      changeset = Setting.changeset(%Setting{}, valid_attrs(%{key: ""}))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).key
    end
  end

  describe "changeset/2 — cast allowlist" do
    test "ignores unknown fields" do
      changeset = Setting.changeset(%Setting{}, valid_attrs(%{not_a_field: "leak"}))
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :not_a_field)
    end
  end
end
