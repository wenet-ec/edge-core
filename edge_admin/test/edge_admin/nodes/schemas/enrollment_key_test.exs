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
        expires_at: nil,
        last_used_at: nil
      },
      overrides
    )
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        key: "somebase64blob==",
        cluster_id: Ecto.UUID.generate(),
        uses_remaining: 1
      },
      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  # ---------------------------------------------------------------------------
  # changeset/2
  # ---------------------------------------------------------------------------

  describe "changeset/2" do
    test "accepts a future expiry" do
      future = DateTime.shift(DateTime.utc_now(), hour: 1)

      assert EnrollmentKey.changeset(%EnrollmentKey{}, valid_attrs(%{expires_at: future})).valid?
    end

    test "rejects a past expiry" do
      past = DateTime.shift(DateTime.utc_now(), hour: -1)
      changeset = EnrollmentKey.changeset(%EnrollmentKey{}, valid_attrs(%{expires_at: past}))

      refute changeset.valid?
      assert "must be in the future" in errors_on(changeset).expires_at
    end

    test "allows a nil expiry for a non-expiring key" do
      assert EnrollmentKey.changeset(%EnrollmentKey{}, valid_attrs(%{expires_at: nil})).valid?
    end

    test "maps the cluster foreign key constraint to the cluster_id field" do
      constraints = EnrollmentKey.changeset(%EnrollmentKey{}, valid_attrs()).constraints

      assert Enum.any?(constraints, fn constraint ->
               constraint.field == :cluster_id and constraint.type == :foreign_key and
                 constraint.error_type == :foreign
             end)
    end
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

    test "uses_remaining == nil (unlimited) → false (not spent)" do
      refute EnrollmentKey.spent?(key(%{uses_remaining: nil}))
    end
  end

  # ---------------------------------------------------------------------------
  # expired?/1
  # ---------------------------------------------------------------------------

  describe "expired?/1" do
    test "nil expires_at → false (never expires)" do
      refute EnrollmentKey.expired?(key(%{expires_at: nil}))
    end

    test "expires_at in the future → false (not expired)" do
      future = DateTime.shift(DateTime.utc_now(), hour: 1)
      refute EnrollmentKey.expired?(key(%{expires_at: future}))
    end

    test "expires_at in the past → true (expired)" do
      past = DateTime.shift(DateTime.utc_now(), hour: -1)
      assert EnrollmentKey.expired?(key(%{expires_at: past}))
    end
  end

  # ---------------------------------------------------------------------------
  # unlimited?/1
  # ---------------------------------------------------------------------------

  describe "unlimited?/1" do
    test "uses_remaining == nil → true (unlimited)" do
      assert EnrollmentKey.unlimited?(key(%{uses_remaining: nil}))
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
