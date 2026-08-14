# edge_admin/lib/edge_admin/encryption/schema_registry.ex
defmodule EdgeAdmin.Encryption.SchemaRegistry do
  @moduledoc """
  Registry of schemas that declare encrypted fields.

  The rotation task walks each schema returned here and re-encrypts every row
  through the active ciphers. Add new schemas here when they declare encrypted
  fields.
  """

  @doc "Returns schemas that have at least one encrypted column."
  @spec schemas() :: [module()]
  def schemas do
    [
      EdgeAdmin.Events.Webhooks.Schemas.Webhook
    ]
  end
end
