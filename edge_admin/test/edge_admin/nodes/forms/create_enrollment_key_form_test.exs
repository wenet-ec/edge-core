# edge_admin/test/edge_admin/nodes/forms/create_enrollment_key_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.CreateEnrollmentKeyFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.CreateEnrollmentKeyForm

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
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{})
      assert result == %{}
    end

    test "uses_remaining of 1 is accepted (boundary)" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => 1})
      assert result["uses_remaining"] == 1
    end

    test "uses_remaining of positive integer is accepted" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => 10})
      assert result["uses_remaining"] == 10
    end

    test "uses_remaining of -1 (unlimited) is accepted" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => -1})
      assert result["uses_remaining"] == -1
    end

    test "expired_at is accepted when a valid datetime" do
      dt = ~U[2027-01-01 00:00:00Z]
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"expired_at" => dt})
      assert result["expired_at"] == dt
    end

    test "both optional fields accepted together" do
      dt = ~U[2027-06-01 12:00:00Z]

      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => 5, "expired_at" => dt})

      assert result["uses_remaining"] == 5
      assert result["expired_at"] == dt
    end

    test "wrapped enrollment_key params are unwrapped" do
      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{
                 "enrollment_key" => %{"uses_remaining" => 3}
               })

      assert result["uses_remaining"] == 3
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — uses_remaining validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — uses_remaining validation" do
    test "zero uses_remaining is rejected" do
      assert {:error, changeset} = CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => 0})
      assert %{uses_remaining: [_msg]} = errors_on(changeset)
    end

    test "negative uses_remaining (other than -1) is rejected" do
      assert {:error, changeset} = CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => -2})
      assert %{uses_remaining: [_msg]} = errors_on(changeset)
    end

    test "error message mentions -1 and positive integer" do
      {:error, changeset} = CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => 0})
      [msg] = errors_on(changeset).uses_remaining
      assert msg =~ "-1"
    end

    test "nil uses_remaining is allowed (excluded from result)" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => nil})
      refute Map.has_key?(result, "uses_remaining")
    end

    test "absent uses_remaining is allowed (excluded from result)" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{})
      refute Map.has_key?(result, "uses_remaining")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "nil optional fields are excluded from result map" do
      {:ok, result} = CreateEnrollmentKeyForm.changeset(%{})
      refute Map.has_key?(result, "uses_remaining")
      refute Map.has_key?(result, "expired_at")
    end

    test "present fields are included in result map" do
      dt = ~U[2027-01-01 00:00:00Z]

      {:ok, result} =
        CreateEnrollmentKeyForm.changeset(%{"uses_remaining" => 2, "expired_at" => dt})

      assert result["uses_remaining"] == 2
      assert result["expired_at"] == dt
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types (fallback clause returns empty map)
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params fall through to empty map (changeset(_) clause)" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset("bad")
      assert result == %{}
    end

    test "nil params fall through to empty map (changeset(_) clause)" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(nil)
      assert result == %{}
    end
  end
end
