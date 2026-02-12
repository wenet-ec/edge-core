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
    test "default key_type with no optional fields succeeds" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"key_type" => "default"})
      assert result["key_type"] == "default"
    end

    test "custom key_type succeeds" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"key_type" => "custom"})
      assert result["key_type"] == "custom"
    end

    test "expiration is accepted when positive" do
      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{"key_type" => "default", "expiration" => 3600})

      assert result["expiration"] == 3600
    end

    test "uses_remaining is accepted when positive" do
      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{
                 "key_type" => "default",
                 "uses_remaining" => 5
               })

      assert result["uses_remaining"] == 5
    end

    test "both optional fields accepted together" do
      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{
                 "key_type" => "custom",
                 "expiration" => 7200,
                 "uses_remaining" => 10
               })

      assert result["key_type"] == "custom"
      assert result["expiration"] == 7200
      assert result["uses_remaining"] == 10
    end

    test "wrapped enrollment_key params are unwrapped" do
      assert {:ok, _result} =
               CreateEnrollmentKeyForm.changeset(%{
                 "enrollment_key" => %{"key_type" => "default"}
               })
    end

    test "expiration of 1 second is accepted (boundary)" do
      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{"key_type" => "default", "expiration" => 1})

      assert result["expiration"] == 1
    end

    test "uses_remaining of 1 is accepted (boundary)" do
      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{
                 "key_type" => "default",
                 "uses_remaining" => 1
               })

      assert result["uses_remaining"] == 1
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — key_type validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — key_type validation" do
    test "missing key_type is rejected" do
      assert {:error, changeset} = CreateEnrollmentKeyForm.changeset(%{})
      assert %{key_type: [_msg]} = errors_on(changeset)
    end

    test "invalid key_type is rejected" do
      assert {:error, changeset} =
               CreateEnrollmentKeyForm.changeset(%{"key_type" => "unlimited"})

      assert %{key_type: [_msg]} = errors_on(changeset)
    end

    test "uppercase key_type is rejected" do
      assert {:error, changeset} =
               CreateEnrollmentKeyForm.changeset(%{"key_type" => "Default"})

      assert %{key_type: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — expiration validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — expiration validation" do
    test "zero expiration is rejected" do
      assert {:error, changeset} =
               CreateEnrollmentKeyForm.changeset(%{"key_type" => "default", "expiration" => 0})

      assert %{expiration: [_msg]} = errors_on(changeset)
    end

    test "negative expiration is rejected" do
      assert {:error, changeset} =
               CreateEnrollmentKeyForm.changeset(%{"key_type" => "default", "expiration" => -1})

      assert %{expiration: [_msg]} = errors_on(changeset)
    end

    test "nil expiration is allowed (optional field)" do
      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{"key_type" => "default", "expiration" => nil})

      refute Map.has_key?(result, "expiration")
    end

    test "absent expiration is allowed (optional field)" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"key_type" => "default"})
      refute Map.has_key?(result, "expiration")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — uses_remaining validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — uses_remaining validation" do
    test "zero uses_remaining is rejected" do
      assert {:error, changeset} =
               CreateEnrollmentKeyForm.changeset(%{
                 "key_type" => "default",
                 "uses_remaining" => 0
               })

      assert %{uses_remaining: [_msg]} = errors_on(changeset)
    end

    test "negative uses_remaining is rejected" do
      assert {:error, changeset} =
               CreateEnrollmentKeyForm.changeset(%{
                 "key_type" => "default",
                 "uses_remaining" => -1
               })

      assert %{uses_remaining: [_msg]} = errors_on(changeset)
    end

    test "nil uses_remaining is allowed (optional field)" do
      assert {:ok, result} =
               CreateEnrollmentKeyForm.changeset(%{
                 "key_type" => "default",
                 "uses_remaining" => nil
               })

      refute Map.has_key?(result, "uses_remaining")
    end

    test "absent uses_remaining is allowed (optional field)" do
      assert {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"key_type" => "default"})
      refute Map.has_key?(result, "uses_remaining")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "nil optional fields are excluded from result map" do
      {:ok, result} = CreateEnrollmentKeyForm.changeset(%{"key_type" => "default"})
      refute Map.has_key?(result, "expiration")
      refute Map.has_key?(result, "uses_remaining")
    end

    test "present optional fields are included in result map" do
      {:ok, result} =
        CreateEnrollmentKeyForm.changeset(%{
          "key_type" => "custom",
          "expiration" => 3600,
          "uses_remaining" => 2
        })

      assert result["key_type"] == "custom"
      assert result["expiration"] == 3600
      assert result["uses_remaining"] == 2
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateEnrollmentKeyForm.changeset("bad")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateEnrollmentKeyForm.changeset(nil)
      end
    end
  end
end
