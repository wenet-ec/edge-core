# edge_admin/lib/edge_admin/ssh/views/ssh_username_view.ex
defmodule EdgeAdmin.Ssh.Views.SshUsernameView do
  @moduledoc """
  Public-facing render for `SshUsername` — the canonical map shape both
  REST and MCP serialize. Includes a derived `has_password` flag and a
  nested array of public keys (without password hashes). Requires
  `ssh_public_keys` to be preloaded.
  """

  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @spec render(SshUsername.t()) :: map()
  def render(%SshUsername{ssh_public_keys: ssh_public_keys} = u) do
    %{
      id: u.id,
      username: u.username,
      has_password: SshUsername.has_password?(u),
      node_id: u.node_id,
      public_keys: Enum.map(ssh_public_keys, &public_key_summary/1),
      inserted_at: u.inserted_at,
      updated_at: u.updated_at
    }
  end

  defp public_key_summary(key) do
    %{
      id: key.id,
      key_name: key.key_name,
      public_key: key.public_key,
      inserted_at: key.inserted_at,
      updated_at: key.updated_at
    }
  end
end
