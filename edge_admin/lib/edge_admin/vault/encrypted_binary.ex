# edge_admin/lib/edge_admin/vault/encrypted_binary.ex
defmodule EdgeAdmin.Vault.EncryptedBinary do
  @moduledoc """
  Ecto type for opaque encrypted binary fields (e.g. HMAC secrets).

  Migration column type: `:binary`. Reads/writes feel like a normal binary
  string at the schema level; the round-trip through Cloak is transparent.
  """

  use Cloak.Ecto.Binary, vault: EdgeAdmin.Vault
end
