# edge_agent/test/edge_agent/ingress/identity_test.exs
defmodule EdgeAgent.Ingress.IdentityTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.Ingress.Identity
  alias EdgeAgent.Settings

  test "creates a durable WireGuard keypair and returns the stable public key" do
    assert Settings.get_ingress_private_key() == nil

    assert {:ok, public_key} = Identity.public_key()
    assert {:ok, private_key} = Base.decode64(Settings.get_ingress_private_key())

    assert byte_size(private_key) == 32
    assert {:ok, decoded_public_key} = Base.decode64(public_key)
    assert byte_size(decoded_public_key) == 32

    case apply(:crypto, :generate_key, [:ecdh, :x25519, private_key]) do
      {derived_public_key, _private_key} when is_binary(derived_public_key) ->
        assert Base.encode64(derived_public_key) == public_key

      result ->
        flunk("unexpected X25519 public-key derivation result: #{inspect(result)}")
    end

    assert {:ok, ^public_key} = Identity.public_key()
  end
end
