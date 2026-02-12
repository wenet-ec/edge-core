defmodule EdgeAdmin.SelfUpdates.Rules.DeletionRulesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.SelfUpdates.Rules.DeletionRules
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  # ---------------------------------------------------------------------------
  # validate_request_deletion/1
  #
  # Pure function: pattern matches on the struct's :status field, no DB call.
  # ---------------------------------------------------------------------------

  describe "validate_request_deletion/1 — completed request" do
    test "completed request returns :ok" do
      request = %SelfUpdateRequest{status: "completed"}
      assert :ok = DeletionRules.validate_request_deletion(request)
    end
  end

  describe "validate_request_deletion/1 — non-completed requests" do
    test "pending request cannot be deleted" do
      request = %SelfUpdateRequest{status: "pending"}
      assert {:error, changeset} = DeletionRules.validate_request_deletion(request)
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "pending"
      assert msg =~ "completed"
    end

    test "processing request cannot be deleted" do
      request = %SelfUpdateRequest{status: "processing"}
      assert {:error, changeset} = DeletionRules.validate_request_deletion(request)
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "processing"
      assert msg =~ "completed"
    end

    test "error message includes the actual failing status" do
      request = %SelfUpdateRequest{status: "pending"}
      {:error, changeset} = DeletionRules.validate_request_deletion(request)
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "pending"
    end
  end

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
