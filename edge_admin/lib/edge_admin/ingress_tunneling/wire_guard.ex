# edge_admin/lib/edge_admin/ingress_tunneling/wire_guard.ex
defmodule EdgeAdmin.IngressTunneling.WireGuard do
  @moduledoc """
  Generates WireGuard X25519 keypairs for Ingress Tunneling identities.
  """

  @curve :x25519

  @type keypair :: %{public_key: String.t(), private_key: String.t()}

  @doc "Generates a canonical base64-encoded 32-byte X25519 keypair."
  @spec generate_keypair() :: keypair()
  def generate_keypair do
    {public_key, private_key} = :crypto.generate_key(:ecdh, @curve)

    if !(is_binary(public_key) and is_binary(private_key) and byte_size(public_key) == 32 and
           byte_size(private_key) == 32) do
      raise ArgumentError, "X25519 key generation returned invalid key material"
    end

    %{public_key: Base.encode64(public_key), private_key: Base.encode64(private_key)}
  end
end
