defmodule EdgeAdmin.SelfUpdates.Checks.DeleteRequestCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.SelfUpdates.Checks.DeleteRequestCheck
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  # ---------------------------------------------------------------------------
  # check/1
  #
  # Pure function: pattern matches on the struct's :status field, no DB call.
  # ---------------------------------------------------------------------------

  describe "check/1 — completed request" do
    test "completed request returns :ok" do
      request = %SelfUpdateRequest{status: "completed"}
      assert :ok = DeleteRequestCheck.check(request)
    end
  end

  describe "check/1 — non-completed requests" do
    test "pending request returns conflict error" do
      request = %SelfUpdateRequest{status: "pending"}
      assert {:error, {:conflict, reason}} = DeleteRequestCheck.check(request)
      assert reason =~ "pending"
      assert reason =~ "completed"
    end

    test "processing request returns conflict error" do
      request = %SelfUpdateRequest{status: "processing"}
      assert {:error, {:conflict, reason}} = DeleteRequestCheck.check(request)
      assert reason =~ "processing"
      assert reason =~ "completed"
    end

    test "error message includes the actual failing status" do
      request = %SelfUpdateRequest{status: "pending"}
      {:error, {:conflict, reason}} = DeleteRequestCheck.check(request)
      assert reason =~ "pending"
    end
  end
end
