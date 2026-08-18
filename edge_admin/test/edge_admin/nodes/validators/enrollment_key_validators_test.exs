# edge_admin/test/edge_admin/nodes/validators/enrollment_key_validators_test.exs
defmodule EdgeAdmin.Nodes.Validators.EnrollmentKeyValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Validators.EnrollmentKeyValidators

  test "validates remaining uses" do
    assert EnrollmentKeyValidators.valid_uses_remaining?(nil)
    assert EnrollmentKeyValidators.valid_uses_remaining?(1)
    refute EnrollmentKeyValidators.valid_uses_remaining?(0)
  end

  test "validates expiry against an explicit clock" do
    now = ~U[2026-01-01 00:00:00Z]
    assert EnrollmentKeyValidators.valid_expiry?(~U[2026-01-01 00:00:01Z], now)
    refute EnrollmentKeyValidators.valid_expiry?(now, now)
  end
end
