# edge_admin/test/edge_admin_web/controllers/changeset_json_test.exs
defmodule EdgeAdminWeb.Controllers.ChangesetJSONTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias EdgeAdminWeb.Controllers.ChangesetJSON

  defp fake_conn do
    Plug.Conn.assign(build_conn(), :request_id, "test-request-id")
  end

  # Build a changeset in memory without hitting the DB.
  defp changeset_with(types, attrs, validations_fn) do
    {%{}, types}
    |> Ecto.Changeset.cast(attrs, Map.keys(types))
    |> validations_fn.()
  end

  defp errors_from(changeset) do
    %{conn: fake_conn(), changeset: changeset}
    |> ChangesetJSON.error()
    |> get_in([:error, :details])
  end

  describe "error/1 — structure" do
    test "returns a map with :error key" do
      cs =
        changeset_with(%{name: :string}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :name, "can't be blank")
        end)

      result = ChangesetJSON.error(%{conn: fake_conn(), changeset: cs})
      assert is_map(result)
      assert Map.has_key?(result, :error)
    end

    test "error.code is validation_failed" do
      cs =
        changeset_with(%{name: :string}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :name, "can't be blank")
        end)

      result = ChangesetJSON.error(%{conn: fake_conn(), changeset: cs})
      assert result.error.code == "validation_failed"
    end

    test "error.details is a map keyed by field atom" do
      cs =
        changeset_with(%{name: :string}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :name, "can't be blank")
        end)

      errors = errors_from(cs)
      assert is_map(errors)
      assert Map.has_key?(errors, :name)
    end

    test "each field maps to a list of error strings" do
      cs =
        changeset_with(%{name: :string}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :name, "can't be blank")
        end)

      errors = errors_from(cs)
      assert is_list(errors.name)
      assert Enum.all?(errors.name, &is_binary/1)
    end
  end

  describe "error/1 — plain messages" do
    test "single error on a field" do
      cs =
        changeset_with(%{email: :string}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :email, "can't be blank")
        end)

      assert errors_from(cs) == %{email: ["can't be blank"]}
    end

    test "multiple errors on the same field" do
      cs =
        changeset_with(%{password: :string}, %{}, fn cs ->
          cs
          |> Ecto.Changeset.add_error(:password, "can't be blank")
          |> Ecto.Changeset.add_error(:password, "is too short")
        end)

      errors = errors_from(cs)
      assert "can't be blank" in errors.password
      assert "is too short" in errors.password
      assert length(errors.password) == 2
    end

    test "errors across multiple fields" do
      cs =
        changeset_with(%{name: :string, email: :string}, %{}, fn cs ->
          cs
          |> Ecto.Changeset.add_error(:name, "can't be blank")
          |> Ecto.Changeset.add_error(:email, "is invalid")
        end)

      errors = errors_from(cs)
      assert errors.name == ["can't be blank"]
      assert errors.email == ["is invalid"]
    end

    test "changeset with no errors returns empty map" do
      cs = changeset_with(%{name: :string}, %{"name" => "Alice"}, fn cs -> cs end)
      assert errors_from(cs) == %{}
    end
  end

  describe "error/1 — opt interpolation in translate_error" do
    test "interpolates %{count} into message" do
      cs =
        changeset_with(%{name: :string}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :name, "should be at least %{count} character(s)", count: 3)
        end)

      assert errors_from(cs) == %{name: ["should be at least 3 character(s)"]}
    end

    test "interpolates %{min} and %{max} placeholders" do
      cs =
        changeset_with(%{age: :integer}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :age, "must be between %{min} and %{max}", min: 18, max: 99)
        end)

      assert errors_from(cs) == %{age: ["must be between 18 and 99"]}
    end

    test "message with no opts is returned as-is" do
      cs =
        changeset_with(%{title: :string}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :title, "is required")
        end)

      assert errors_from(cs) == %{title: ["is required"]}
    end

    test "unknown placeholder left unchanged when key not in opts" do
      cs =
        changeset_with(%{x: :string}, %{}, fn cs ->
          Ecto.Changeset.add_error(cs, :x, "must match %{pattern}", [])
        end)

      assert errors_from(cs) == %{x: ["must match %{pattern}"]}
    end
  end

  describe "error/1 — validate_length style errors" do
    test "validate_length generates interpolated count message" do
      cs =
        changeset_with(%{username: :string}, %{"username" => "ab"}, fn cs ->
          Ecto.Changeset.validate_length(cs, :username, min: 5)
        end)

      errors = errors_from(cs)
      assert length(errors.username) == 1
      assert hd(errors.username) =~ "5"
    end
  end
end
