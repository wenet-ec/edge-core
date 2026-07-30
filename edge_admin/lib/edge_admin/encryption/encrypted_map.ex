# edge_admin/lib/edge_admin/encryption/encrypted_map.ex
defmodule EdgeAdmin.Encryption.EncryptedMap do
  @moduledoc """
  Ecto type for encrypted map fields (e.g. webhook header maps).

  Migration column type: `:binary`. Reads/writes feel like a normal map at
  the schema level — Cloak JSON-encodes the map, encrypts the bytes, and
  reverses on read.
  """

  use Cloak.Ecto.Map, vault: EdgeAdmin.Encryption
end
