# edge_agent/test/edge_agent_web/controllers/changeset_json_test.exs
defmodule EdgeAgentWeb.Controllers.ChangesetJSONTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  import Phoenix.ConnTest

  alias EdgeAgentWeb.Controllers.ChangesetJSON

  defp fake_conn do
    Plug.Conn.assign(build_conn(), :request_id, "test-request-id")
  end

  defp changeset_with_errors(types, changes, validations_fn) do
    {%{}, types}
    |> cast(changes, Map.keys(types))
    |> validations_fn.()
  end

  defp errors_from(changeset) do
    %{conn: fake_conn(), changeset: changeset}
    |> ChangesetJSON.error()
    |> get_in([:error, :details])
  end

  describe "error/1 — envelope structure" do
    test "returns a map with :error key" do
      cs = changeset_with_errors(%{name: :string}, %{}, &validate_required(&1, [:name]))
      result = ChangesetJSON.error(%{conn: fake_conn(), changeset: cs})
      assert Map.has_key?(result, :error)
    end

    test "error.code is validation_failed" do
      cs = changeset_with_errors(%{name: :string}, %{}, &validate_required(&1, [:name]))
      result = ChangesetJSON.error(%{conn: fake_conn(), changeset: cs})
      assert result.error.code == "validation_failed"
    end

    test "error.message is set" do
      cs = changeset_with_errors(%{name: :string}, %{}, &validate_required(&1, [:name]))
      result = ChangesetJSON.error(%{conn: fake_conn(), changeset: cs})
      assert is_binary(result.error.message)
    end

    test "meta is present with request_id and timestamp" do
      cs = changeset_with_errors(%{name: :string}, %{}, &validate_required(&1, [:name]))
      result = ChangesetJSON.error(%{conn: fake_conn(), changeset: cs})
      assert result.meta.request_id == "test-request-id"
      assert is_binary(result.meta.timestamp)
    end

    test "error.details is a map keyed by field atom" do
      cs = changeset_with_errors(%{name: :string}, %{}, &validate_required(&1, [:name]))
      assert Map.has_key?(errors_from(cs), :name)
    end

    test "each field maps to a list of error strings" do
      cs = changeset_with_errors(%{name: :string}, %{}, &validate_required(&1, [:name]))
      errors = errors_from(cs)
      assert is_list(errors.name)
      assert Enum.all?(errors.name, &is_binary/1)
    end
  end

  describe "error/1 — field errors" do
    test "single field error" do
      cs = changeset_with_errors(%{name: :string}, %{}, &validate_required(&1, [:name]))
      assert %{name: [_ | _]} = errors_from(cs)
    end

    test "multiple fields each have their own errors" do
      cs =
        changeset_with_errors(%{name: :string, email: :string}, %{}, fn cs ->
          validate_required(cs, [:name, :email])
        end)

      errors = errors_from(cs)
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

      assert length(errors_from(cs).name) == 2
    end

    test "empty changeset has no field errors" do
      cs = changeset_with_errors(%{name: :string}, %{}, fn cs -> cs end)
      assert errors_from(cs) == %{}
    end
  end

  describe "error/1 — translate_error interpolation" do
    test "message with no placeholders is returned as-is" do
      cs = changeset_with_errors(%{name: :string}, %{}, &validate_required(&1, [:name]))
      [msg | _] = errors_from(cs).name
      assert is_binary(msg)
    end

    test "%{count} placeholder is interpolated for validate_length" do
      cs =
        changeset_with_errors(%{name: :string}, %{"name" => "ab"}, fn cs ->
          validate_length(cs, :name, min: 5)
        end)

      [msg] = errors_from(cs).name
      assert msg =~ "5"
      refute msg =~ "%{count}"
    end

    test "%{min} and %{max} placeholders are interpolated" do
      cs =
        changeset_with_errors(%{age: :integer}, %{"age" => 3}, fn cs ->
          validate_number(cs, :age, greater_than_or_equal_to: 18, less_than_or_equal_to: 65)
        end)

      [msg] = errors_from(cs).age
      assert is_binary(msg)
      refute msg =~ "%{"
    end
  end
end
