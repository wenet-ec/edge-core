# edge_admin/lib/edge_admin_mcp/tools/ssh/ssh_username_data.ex
defmodule EdgeAdminMcp.Tools.Ssh.SshUsernameData do
  @moduledoc false

  alias EdgeAdmin.Ssh.Schemas.SshUsername

  def data(%SshUsername{ssh_public_keys: ssh_public_keys} = u) do
    %{
      id: u.id,
      username: u.username,
      has_password: SshUsername.has_password?(u),
      node_id: u.node_id,
      public_keys:
        Enum.map(ssh_public_keys, fn key ->
          %{
            id: key.id,
            key_name: key.key_name,
            public_key: key.public_key,
            inserted_at: key.inserted_at,
            updated_at: key.updated_at
          }
        end),
      inserted_at: u.inserted_at,
      updated_at: u.updated_at
    }
  end
end
