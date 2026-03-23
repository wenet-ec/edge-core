# edge_admin/lib/edge_admin/mcp/tools/ssh/get_ssh_public_key.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.GetSshPublicKey do
  @moduledoc "Get an SSH public key by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Ssh.SshPublicKeyData
  alias EdgeAdmin.Ssh

  schema do
    field :ssh_public_key_id, {:required, :string}
  end

  @impl true
  def execute(%{ssh_public_key_id: id}, frame) do
    case Ssh.get_ssh_public_key(id) do
      {:ok, key} ->
        {:reply, Response.json(Response.tool(), SshPublicKeyData.data(key)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "SSH public key #{id} not found"), frame}
    end
  end
end
