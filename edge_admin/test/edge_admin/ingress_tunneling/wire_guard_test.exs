# edge_admin/test/edge_admin/ingress_tunneling/wire_guard_test.exs
defmodule EdgeAdmin.IngressTunneling.WireGuardTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.IngressTunneling.WireGuard

  test "generates a 32-byte X25519 keypair with a public key derived from its private key" do
    assert %{public_key: encoded_public_key, private_key: encoded_private_key} = WireGuard.generate_keypair()
    assert {:ok, public_key} = Base.decode64(encoded_public_key)
    assert {:ok, private_key} = Base.decode64(encoded_private_key)
    assert byte_size(public_key) == 32
    assert byte_size(private_key) == 32

    case apply(:crypto, :generate_key, [:ecdh, :x25519, private_key]) do
      {derived_public_key, _private_key} when is_binary(derived_public_key) ->
        assert Base.encode64(derived_public_key) == encoded_public_key

      derived_public_key when is_binary(derived_public_key) ->
        assert Base.encode64(derived_public_key) == encoded_public_key
    end
  end
end
