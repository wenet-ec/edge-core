# edge_admin/test/edge_admin/nodes/forms/verify_enrollment_key_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.VerifyEnrollmentKeyFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.VerifyEnrollmentKeyForm

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
    test "valid key blob returns {:ok, key_string}" do
      blob = "eyJhZG1pbl91cmxzIjpbImh0dHBzOi8vYWRtaW4uZXhhbXBsZS5jb20iXX0="
      assert {:ok, result} = VerifyEnrollmentKeyForm.changeset(%{"key" => blob})
      assert result == blob
    end

    test "result is the key string directly, not a map" do
      blob = "somebase64blob=="
      assert {:ok, result} = VerifyEnrollmentKeyForm.changeset(%{"key" => blob})
      assert is_binary(result)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — key validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — key validation" do
    test "missing key field is rejected" do
      assert {:error, changeset} = VerifyEnrollmentKeyForm.changeset(%{})
      assert %{key: [_msg]} = errors_on(changeset)
    end

    test "nil key is rejected" do
      assert {:error, changeset} = VerifyEnrollmentKeyForm.changeset(%{"key" => nil})
      assert %{key: [_msg]} = errors_on(changeset)
    end

    test "empty string key is rejected" do
      assert {:error, changeset} = VerifyEnrollmentKeyForm.changeset(%{"key" => ""})
      assert %{key: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types (fallback returns {:error, :invalid})
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params return {:error, :invalid}" do
      assert {:error, :invalid} = VerifyEnrollmentKeyForm.changeset("bad")
    end

    test "nil params return {:error, :invalid}" do
      assert {:error, :invalid} = VerifyEnrollmentKeyForm.changeset(nil)
    end
  end
end
