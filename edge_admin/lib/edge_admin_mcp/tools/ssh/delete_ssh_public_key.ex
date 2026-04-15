# edge_admin/lib/edge_admin_mcp/tools/ssh/delete_ssh_public_key.ex
defmodule EdgeAdminMcp.Tools.Ssh.DeleteSshPublicKey do
  @moduledoc "Delete an SSH public key."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :ssh_public_key_id, {:required, :string}
  end

  @impl true
  def execute(%{ssh_public_key_id: id}, frame) do
    with {:ok, key} <- Ssh.get_ssh_public_key(id),
         {:ok, _} <- Ssh.delete_ssh_public_key(key) do
      {:reply, Response.text(Response.tool(), "SSH public key #{id} deleted"), frame}
    else
      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "SSH public key #{id} not found")), frame}

      {:error, reason} ->
        {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
    end
  end
end
