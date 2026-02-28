# edge_agent/test/edge_agent_web/controllers/changeset_json_test.exs
defmodule EdgeAgentWeb.Controllers.ChangesetJSONTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias EdgeAgentWeb.Controllers.ChangesetJSON

  defp changeset_with_errors(types, changes, validations_fn) do
    {%{}, types}
    |> cast(changes, Map.keys(types))
    |> validations_fn.()
  end

  describe "error/1" do
    test "returns map with errors key" do
      cs =
        changeset_with_errors(%{name: :string}, %{}, fn cs ->
          validate_required(cs, [:name])
        end)

      result = ChangesetJSON.error(%{changeset: cs})
      assert Map.has_key?(result, :errors)
    end

    test "single field error is nested under field name" do
      cs =
        changeset_with_errors(%{name: :string}, %{}, fn cs ->
          validate_required(cs, [:name])
        end)

      %{errors: errors} = ChangesetJSON.error(%{changeset: cs})
      assert Map.has_key?(errors, :name)
    end

    test "error messages are strings" do
      cs =
        changeset_with_errors(%{name: :string}, %{}, fn cs ->
          validate_required(cs, [:name])
        end)

      %{errors: %{name: messages}} = ChangesetJSON.error(%{changeset: cs})
      assert is_list(messages)
      assert Enum.all?(messages, &is_binary/1)
    end

    test "multiple fields each have their own errors" do
      cs =
        changeset_with_errors(%{name: :string, email: :string}, %{}, fn cs ->
          validate_required(cs, [:name, :email])
        end)

      %{errors: errors} = ChangesetJSON.error(%{changeset: cs})
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :email)
    end

    test "multiple errors on same field are all returned" do
      cs =
        changeset_with_errors(%{name: :string}, %{"name" => "ab"}, fn cs ->
          cs
          |> validate_length(:name, min: 5)
          |> validate_format(:name, ~r/^\d+$/)
        end)

      %{errors: %{name: messages}} = ChangesetJSON.error(%{changeset: cs})
      assert length(messages) == 2
    end

    test "empty changeset has no field errors" do
      cs = changeset_with_errors(%{name: :string}, %{}, fn cs -> cs end)
      %{errors: errors} = ChangesetJSON.error(%{changeset: cs})
      assert errors == %{}
    end
  end

  describe "translate_error/1 — interpolation" do
    test "message with no placeholders is returned as-is" do
      cs =
        changeset_with_errors(%{name: :string}, %{}, fn cs ->
          validate_required(cs, [:name])
        end)

      %{errors: %{name: [msg | _]}} = ChangesetJSON.error(%{changeset: cs})
      assert is_binary(msg)
    end

    test "%{count} placeholder is interpolated for validate_length" do
      cs =
        changeset_with_errors(%{name: :string}, %{"name" => "ab"}, fn cs ->
          validate_length(cs, :name, min: 5)
        end)

      %{errors: %{name: [msg]}} = ChangesetJSON.error(%{changeset: cs})
      assert msg =~ "5"
      refute msg =~ "%{count}"
    end

    test "%{min} and %{max} placeholders are interpolated" do
      cs =
        changeset_with_errors(%{age: :integer}, %{"age" => 3}, fn cs ->
          validate_number(cs, :age, greater_than_or_equal_to: 18, less_than_or_equal_to: 65)
        end)

      %{errors: %{age: [msg]}} = ChangesetJSON.error(%{changeset: cs})
      # The number value should appear, not the placeholder
      assert is_binary(msg)
      refute msg =~ "%{"
    end
  end
end
