# edge_admin/lib/edge_admin/nodes/validators/enrollment_key_validators.ex
defmodule EdgeAdmin.Nodes.Validators.EnrollmentKeyValidators do
  @moduledoc "Pure value-level validators for enrollment keys."

  @spec valid_uses_remaining?(term()) :: boolean()
  def valid_uses_remaining?(nil), do: true
  def valid_uses_remaining?(uses_remaining) when is_integer(uses_remaining), do: uses_remaining > 0
  def valid_uses_remaining?(_uses_remaining), do: false

  @spec valid_expiry?(term(), DateTime.t()) :: boolean()
  def valid_expiry?(%DateTime{} = expires_at, %DateTime{} = now), do: DateTime.after?(expires_at, now)
  def valid_expiry?(_expires_at, _now), do: false
end
