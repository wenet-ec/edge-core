# edge_admin/lib/edge_admin/mcp/tools/ssh/ssh_public_key_data.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.SshPublicKeyData do
  @moduledoc false

  alias EdgeAdmin.Ssh.Schemas.SshPublicKey

  def data(%SshPublicKey{} = key) do
    %{
      id: key.id,
      public_key: key.public_key,
      key_name: key.key_name,
      ssh_username_id: key.ssh_username_id,
      inserted_at: key.inserted_at,
      updated_at: key.updated_at
    }
  end
end
