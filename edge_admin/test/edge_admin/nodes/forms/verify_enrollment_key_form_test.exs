# edge_admin/test/edge_admin/nodes/forms/verify_enrollment_key_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.VerifyEnrollmentKeyFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.VerifyEnrollmentKeyForm
  # helpers

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # changeset/1 — valid cases

  describe "changeset/1 — valid cases" do
    test "valid key blob returns a normalized map" do
      blob = "eyJhZG1pbl91cmxzIjpbImh0dHBzOi8vYWRtaW4uZXhhbXBsZS5jb20iXX0="
      assert {:ok, %{"key" => ^blob}} = VerifyEnrollmentKeyForm.changeset(%{"key" => blob})
    end

    test "result preserves the key string in the map" do
      blob = "somebase64blob=="
      assert {:ok, %{"key" => ^blob}} = VerifyEnrollmentKeyForm.changeset(%{"key" => blob})
    end
  end

  # changeset/1 — key validation

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

  # changeset/1 — invalid param types

  describe "changeset/1 — invalid params" do
    test "non-map params return a base error" do
      assert {:error, changeset} = VerifyEnrollmentKeyForm.changeset("bad")
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end

    test "nil params return a base error" do
      assert {:error, changeset} = VerifyEnrollmentKeyForm.changeset(nil)
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end
  end
end
