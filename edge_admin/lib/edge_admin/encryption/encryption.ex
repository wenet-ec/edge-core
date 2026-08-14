# edge_admin/lib/edge_admin/encryption/encryption.ex
defmodule EdgeAdmin.Encryption do
  @moduledoc """
  Encryption-at-rest boundary for sensitive Ecto columns.

  Configured at runtime in `runtime.exs` from `ENCRYPTION_KEY` and
  `ENCRYPTION_TAG`. The key is 32 bytes of base64; the tag pairs 1:1 with the
  key and is prepended to every ciphertext blob so the encryption library can
  find the right cipher on decrypt. This makes rotation possible without
  DB-side bookkeeping.

  Both env vars are required at boot — same shape as `MASTER_KEY` and
  `SECRET_KEY_BASE`. There is no optional-encryption branch; lite/example
  configs ship a generated key like they ship `SECRET_KEY_BASE`.

  ## Usage in schemas

      field :secret,  EdgeAdmin.Encryption.EncryptedBinary
      field :headers, EdgeAdmin.Encryption.EncryptedMap

  ## Rotation

  See `EdgeAdmin.Release.rotate_encryption_key/0`. The release task is idempotent
  and gated on the four `ROTATE_*` env vars; if any is missing it logs skip
  and returns. Adding the four envs and re-running the task is safe whether
  the rows are pre-rotation, post-rotation, or partially migrated.
  """

  use Cloak.Vault, otp_app: :edge_admin
end
