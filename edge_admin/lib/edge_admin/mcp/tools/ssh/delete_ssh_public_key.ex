# edge_admin/lib/edge_admin/mcp/tools/ssh/delete_ssh_public_key.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.DeleteSshPublicKey do
  @moduledoc "Delete an SSH public key."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :ssh_public_key_id, :string, required: true
  end

  @impl true
  def execute(%{ssh_public_key_id: id}, frame) do
    with {:ok, key} <- Ssh.get_ssh_public_key(id),
         {:ok, _} <- Ssh.delete_ssh_public_key(key) do
      {:reply, Response.text(Response.tool(), "SSH public key #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "SSH public key #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
