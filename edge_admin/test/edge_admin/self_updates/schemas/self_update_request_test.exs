# edge_admin/test/edge_admin/self_updates/schemas/self_update_request_test.exs
defmodule EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequestTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        targeting: %{"type" => "all"}
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

  describe "changeset/2" do
    test "valid attrs produce a valid changeset" do
      changeset = SelfUpdateRequest.changeset(%SelfUpdateRequest{}, valid_attrs())
      assert changeset.valid?
    end

    test "targeting is required" do
      changeset =
        SelfUpdateRequest.changeset(%SelfUpdateRequest{}, Map.delete(valid_attrs(), :targeting))

      refute changeset.valid?
      assert %{targeting: ["can't be blank"]} = errors_on(changeset)
    end

    test "status is optional (defaults to 'pending' at the schema level)" do
      changeset = SelfUpdateRequest.changeset(%SelfUpdateRequest{}, valid_attrs())
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :status)
    end

    test "summary is optional" do
      changeset = SelfUpdateRequest.changeset(%SelfUpdateRequest{}, valid_attrs())
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :summary)
    end

    test "status accepts the three documented values" do
      for status <- ["pending", "processing", "completed"] do
        changeset = SelfUpdateRequest.changeset(%SelfUpdateRequest{}, valid_attrs(%{status: status}))

        assert changeset.valid?, "expected status #{inspect(status)} to be valid"
      end
    end

    test "status rejects anything not in the documented set" do
      # Note: empty string and whitespace-only are dropped to nil by Ecto's
      # cast/3 default empty_values, so validate_inclusion never sees them.
      # We don't pin those here — that's cast behaviour, not the inclusion check.
      for status <- ["draft", "failed", "cancelled", "PENDING"] do
        changeset = SelfUpdateRequest.changeset(%SelfUpdateRequest{}, valid_attrs(%{status: status}))

        refute changeset.valid?, "expected status #{inspect(status)} to be rejected"
      end
    end

    test "ignores unknown fields (cast allowlist)" do
      attrs = valid_attrs(%{not_a_field: "ignored"})
      changeset = SelfUpdateRequest.changeset(%SelfUpdateRequest{}, attrs)
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :not_a_field)
    end

    test "passes summary map through unchanged" do
      summary = %{"total" => 10, "triggered" => 8, "failed" => 2}

      changeset =
        SelfUpdateRequest.changeset(%SelfUpdateRequest{}, valid_attrs(%{summary: summary}))

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :summary) == summary
    end
  end
end
