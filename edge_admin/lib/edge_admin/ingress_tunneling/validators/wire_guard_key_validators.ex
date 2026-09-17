# edge_admin/lib/edge_admin/ingress_tunneling/validators/wire_guard_key_validators.ex
defmodule EdgeAdmin.IngressTunneling.Validators.WireGuardKeyValidators do
  @moduledoc """
  Validates the common serialized representation of WireGuard key material.

  WireGuard public and private keys are both canonically base64-encoded
  32-byte values. This validator verifies that shared representation only; it
  cannot determine key type or verify that a public and private key form a
  pair.
  """

  @doc "Returns whether a value is canonical base64-encoded WireGuard key material."
  @spec valid_key_material?(term()) :: boolean()
  def valid_key_material?(key) when is_binary(key) do
    with {:ok, decoded} <- Base.decode64(key),
         true <- byte_size(decoded) == 32 do
      Base.encode64(decoded) == key
    else
      _ -> false
    end
  end

  def valid_key_material?(_key), do: false
end
