# edge_admin/test/edge_admin/nodes/schemas/enrollment_key_test.exs
defmodule EdgeAdmin.Nodes.Schemas.EnrollmentKeyTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp key(overrides) do
    Map.merge(
      %EnrollmentKey{
        id: "some-uuid",
        key: "somebase64blob==",
        cluster_id: "cluster-uuid",
        uses_remaining: 1,
        expired_at: nil,
        last_used_at: nil
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # spent?/1
  # ---------------------------------------------------------------------------

  describe "spent?/1" do
    test "uses_remaining == 0 → true (spent)" do
      assert EnrollmentKey.spent?(key(%{uses_remaining: 0}))
    end

    test "uses_remaining == 1 → false (not spent)" do
      refute EnrollmentKey.spent?(key(%{uses_remaining: 1}))
    end

    test "uses_remaining > 1 → false (not spent)" do
      refute EnrollmentKey.spent?(key(%{uses_remaining: 5}))
    end

    test "uses_remaining == -1 (unlimited) → false (not spent)" do
      refute EnrollmentKey.spent?(key(%{uses_remaining: -1}))
    end
  end

  # ---------------------------------------------------------------------------
  # expired?/1
  # ---------------------------------------------------------------------------

  describe "expired?/1" do
    test "nil expired_at → false (never expires)" do
      refute EnrollmentKey.expired?(key(%{expired_at: nil}))
    end

    test "expired_at in the future → false (not expired)" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      refute EnrollmentKey.expired?(key(%{expired_at: future}))
    end

    test "expired_at in the past → true (expired)" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert EnrollmentKey.expired?(key(%{expired_at: past}))
    end
  end

  # ---------------------------------------------------------------------------
  # unlimited?/1
  # ---------------------------------------------------------------------------

  describe "unlimited?/1" do
    test "uses_remaining == -1 → true (unlimited)" do
      assert EnrollmentKey.unlimited?(key(%{uses_remaining: -1}))
    end

    test "uses_remaining == 1 → false (not unlimited)" do
      refute EnrollmentKey.unlimited?(key(%{uses_remaining: 1}))
    end

    test "uses_remaining == 0 → false (not unlimited)" do
      refute EnrollmentKey.unlimited?(key(%{uses_remaining: 0}))
    end

    test "uses_remaining > 1 → false (not unlimited)" do
      refute EnrollmentKey.unlimited?(key(%{uses_remaining: 10}))
    end
  end
end
