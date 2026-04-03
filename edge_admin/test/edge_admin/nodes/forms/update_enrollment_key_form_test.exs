# edge_admin/test/edge_admin/nodes/forms/update_enrollment_key_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.UpdateEnrollmentKeyFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.UpdateEnrollmentKeyForm

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid cases" do
    test "empty attrs succeeds (both fields optional)" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(%{})
      assert result == %{}
    end

    test "uses_remaining of 1 is accepted (boundary)" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(%{uses_remaining: 1})
      assert result["uses_remaining"] == 1
    end

    test "uses_remaining of positive integer is accepted" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(%{uses_remaining: 5})
      assert result["uses_remaining"] == 5
    end

    test "expired_at is accepted when a valid datetime" do
      dt = ~U[2027-01-01 00:00:00Z]
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(%{expired_at: dt})
      assert result["expired_at"] == dt
    end

    test "both fields accepted together" do
      dt = ~U[2027-06-01 12:00:00Z]

      assert {:ok, result} =
               UpdateEnrollmentKeyForm.changeset(%{uses_remaining: 3, expired_at: dt})

      assert result["uses_remaining"] == 3
      assert result["expired_at"] == dt
    end

    test "wrapped enrollment_key params are unwrapped (atom key)" do
      assert {:ok, result} =
               UpdateEnrollmentKeyForm.changeset(%{
                 enrollment_key: %{uses_remaining: 7}
               })

      assert result["uses_remaining"] == 7
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — uses_remaining validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — uses_remaining validation" do
    test "zero uses_remaining is rejected" do
      assert {:error, changeset} = UpdateEnrollmentKeyForm.changeset(%{uses_remaining: 0})
      assert %{uses_remaining: [_msg]} = errors_on(changeset)
    end

    test "negative uses_remaining is rejected" do
      assert {:error, changeset} = UpdateEnrollmentKeyForm.changeset(%{uses_remaining: -2})
      assert %{uses_remaining: [_msg]} = errors_on(changeset)
    end

    test "error message mentions positive integer and null" do
      {:error, changeset} = UpdateEnrollmentKeyForm.changeset(%{uses_remaining: 0})
      [msg] = errors_on(changeset).uses_remaining
      assert msg =~ "positive integer"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — explicit null vs omitted (preserve_null semantics)
  # ---------------------------------------------------------------------------

  describe "changeset/1 — explicit null vs omitted" do
    test "key present with nil value is preserved in result (explicit null)" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(%{expired_at: nil})
      assert Map.has_key?(result, "expired_at")
      assert result["expired_at"] == nil
    end

    test "key present with nil uses_remaining is preserved (explicit null = unlimited)" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(%{uses_remaining: nil})
      assert Map.has_key?(result, "uses_remaining")
      assert result["uses_remaining"] == nil
    end

    test "absent key is excluded from result (omitted field)" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(%{})
      refute Map.has_key?(result, "expired_at")
      refute Map.has_key?(result, "uses_remaining")
    end

    test "only the provided keys appear in result" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(%{uses_remaining: 5})
      assert Map.has_key?(result, "uses_remaining")
      refute Map.has_key?(result, "expired_at")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types (fallback returns empty map)
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params return empty map (changeset(_) fallback clause)" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset("bad")
      assert result == %{}
    end

    test "nil params return empty map (changeset(_) fallback clause)" do
      assert {:ok, result} = UpdateEnrollmentKeyForm.changeset(nil)
      assert result == %{}
    end
  end
end
