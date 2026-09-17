# edge_admin/test/edge_admin/ingress_tunneling/validators/wire_guard_key_validators_test.exs
defmodule EdgeAdmin.IngressTunneling.Validators.WireGuardKeyValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.IngressTunneling.Validators.WireGuardKeyValidators

  test "accepts canonical base64-encoded 32-byte key material" do
    key = Base.encode64(:binary.copy(<<0>>, 32))

    assert WireGuardKeyValidators.valid_key_material?(key)
  end

  test "rejects non-canonical, malformed, incorrectly sized, and non-binary values" do
    key = :binary.copy(<<0>>, 32)

    refute WireGuardKeyValidators.valid_key_material?(Base.encode64(key, padding: false))
    refute WireGuardKeyValidators.valid_key_material?("not-a-wireguard-key")
    refute WireGuardKeyValidators.valid_key_material?(Base.encode64(<<0::248>>))
    refute WireGuardKeyValidators.valid_key_material?(nil)
  end
end
