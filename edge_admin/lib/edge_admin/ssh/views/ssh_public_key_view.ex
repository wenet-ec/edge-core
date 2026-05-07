# edge_admin/lib/edge_admin/ssh/views/ssh_public_key_view.ex
defmodule EdgeAdmin.Ssh.Views.SshPublicKeyView do
  @moduledoc """
  Public-facing render for `SshPublicKey` — the canonical map shape both
  REST and MCP serialize.
  """

  alias EdgeAdmin.Ssh.Schemas.SshPublicKey

  @spec render(SshPublicKey.t()) :: map()
  def render(%SshPublicKey{} = key) do
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
