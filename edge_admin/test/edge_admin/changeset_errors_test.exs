# edge_admin/test/edge_admin/changeset_errors_test.exs
defmodule EdgeAdmin.ChangesetErrorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.ChangesetErrors

  # ---------------------------------------------------------------------------
  # Test fixtures: tiny embedded schemas standing in for real Forms / Schemas.
  # We need a real Ecto.Changeset to feed traverse/1 and to_flat_string/1, but
  # we don't want to depend on any concrete domain schema — those drift.
  # ---------------------------------------------------------------------------

  defmodule Inner do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :type, :string
    end

    def changeset(struct, attrs) do
      struct
      |> cast(attrs, [:type])
      |> validate_required([:type])
      |> validate_inclusion(:type, ["a", "b"])
    end
  end

  defmodule Outer do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :name, :string
      field :age, :integer
      embeds_one :targeting, EdgeAdmin.ChangesetErrorsTest.Inner
    end

    def changeset(struct, attrs) do
      struct
      |> cast(attrs, [:name, :age])
      |> cast_embed(:targeting)
      |> validate_required([:name])
      |> validate_length(:name, min: 3)
      |> validate_number(:age, greater_than: 0)
    end
  end

  defp valid_changeset, do: Outer.changeset(%Outer{}, %{name: "abc", age: 1})

  # ---------------------------------------------------------------------------
  # traverse/1
  # ---------------------------------------------------------------------------

  describe "traverse/1" do
    test "returns an empty map when the changeset has no errors" do
      assert ChangesetErrors.traverse(valid_changeset()) == %{}
    end

    test "returns a map of field => [interpolated message] for top-level errors" do
      changeset = Outer.changeset(%Outer{}, %{})

      result = ChangesetErrors.traverse(changeset)

      assert result == %{name: ["can't be blank"]}
    end

    test "interpolates %{count}-style placeholders in messages" do
      changeset = Outer.changeset(%Outer{}, %{name: "ab", age: 1})

      result = ChangesetErrors.traverse(changeset)

      assert result.name == ["should be at least 3 character(s)"]
    end

    test "interpolates %{number}-style placeholders" do
      changeset = Outer.changeset(%Outer{}, %{name: "abc", age: 0})

      result = ChangesetErrors.traverse(changeset)

      assert result.age == ["must be greater than 0"]
    end

    test "nests errors under the embedded field name" do
      changeset = Outer.changeset(%Outer{}, %{name: "abc", age: 1, targeting: %{type: "x"}})

      result = ChangesetErrors.traverse(changeset)

      # Inner field's :validate_inclusion fires; outer is otherwise valid.
      assert result == %{targeting: %{type: ["is invalid"]}}
    end

    test "produces multiple messages per field when several validators fail" do
      # name: blank AND too short are both checked. validate_required fires
      # on missing keys; on blank-string, validate_required adds 'can't be
      # blank' too. validate_length is a non-required check so it skips
      # blank strings — so we exercise multi-error by combining a
      # too-short name with an out-of-range age (one each).
      changeset = Outer.changeset(%Outer{}, %{name: "ab", age: -1})

      result = ChangesetErrors.traverse(changeset)

      assert result.name == ["should be at least 3 character(s)"]
      assert result.age == ["must be greater than 0"]
    end
  end

  # ---------------------------------------------------------------------------
  # to_flat_string/1
  # ---------------------------------------------------------------------------

  describe "to_flat_string/1" do
    test "returns 'Validation failed' (no detail) when no errors are present" do
      assert ChangesetErrors.to_flat_string(valid_changeset()) == "Validation failed"
    end

    test "renders a single top-level error" do
      changeset = Outer.changeset(%Outer{}, %{})

      assert ChangesetErrors.to_flat_string(changeset) ==
               "Validation failed: name can't be blank"
    end

    test "joins multiple errors with semicolons" do
      changeset = Outer.changeset(%Outer{}, %{name: "ab", age: -1})

      result = ChangesetErrors.to_flat_string(changeset)

      assert String.starts_with?(result, "Validation failed: ")

      # do_flatten prepends, so the final order is reversed relative to
      # iteration; we don't pin order — just the parts.
      tail = String.replace_prefix(result, "Validation failed: ", "")
      parts = String.split(tail, "; ")

      assert "name should be at least 3 character(s)" in parts
      assert "age must be greater than 0" in parts
      assert length(parts) == 2
    end

    test "joins nested embed paths with a dot" do
      changeset = Outer.changeset(%Outer{}, %{name: "abc", age: 1, targeting: %{type: "x"}})

      assert ChangesetErrors.to_flat_string(changeset) ==
               "Validation failed: targeting.type is invalid"
    end

    test "interpolates placeholders the same way traverse/1 does (single-source contract)" do
      # The whole point of this module is that REST and MCP render identical
      # text. to_flat_string is built from traverse, so locking that in here
      # protects the cross-surface contract.
      changeset = Outer.changeset(%Outer{}, %{name: "ab", age: 1})

      flat = ChangesetErrors.to_flat_string(changeset)
      [traverse_msg] = ChangesetErrors.traverse(changeset).name

      assert String.contains?(flat, traverse_msg)
    end
  end
end
