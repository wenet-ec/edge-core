# edge_agent/lib/edge_agent/ingress_tunneling/derp/crypto.ex
defmodule EdgeAgent.IngressTunneling.Derp.Crypto do
  @moduledoc "Seals and opens DERP-compatible NaCl boxes using WireGuard public identities."

  @key_size 32
  @nonce_size 24
  @mac_size 16

  @spec seal(binary(), binary(), binary()) :: {:ok, binary()} | {:error, :invalid_key}
  def seal(public_key, private_key, message)
      when is_binary(public_key) and byte_size(public_key) == @key_size and is_binary(private_key) and
             byte_size(private_key) == @key_size and is_binary(message) do
    nonce = :crypto.strong_rand_bytes(@nonce_size)

    case :libsodium_crypto_box.easy(message, nonce, public_key, private_key) do
      ciphertext when is_binary(ciphertext) -> {:ok, nonce <> ciphertext}
      _error -> {:error, :invalid_key}
    end
  rescue
    _error -> {:error, :invalid_key}
  end

  def seal(_public_key, _private_key, _message), do: {:error, :invalid_key}

  # The port driver allocates a plaintext buffer from ciphertext size minus the MAC.
  @spec open(binary(), binary(), binary()) :: {:ok, binary()} | {:error, :invalid_box}
  def open(public_key, private_key, <<nonce::binary-size(@nonce_size), ciphertext::binary>>)
      when is_binary(public_key) and byte_size(public_key) == @key_size and is_binary(private_key) and
             byte_size(private_key) == @key_size and byte_size(ciphertext) > @mac_size do
    case :libsodium_crypto_box.open_easy(ciphertext, nonce, public_key, private_key) do
      message when is_binary(message) -> {:ok, message}
      _error -> {:error, :invalid_box}
    end
  rescue
    _error -> {:error, :invalid_box}
  end

  def open(_public_key, _private_key, _box), do: {:error, :invalid_box}
end
