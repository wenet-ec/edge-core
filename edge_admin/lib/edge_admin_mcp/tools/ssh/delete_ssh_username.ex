# edge_admin/lib/edge_admin_mcp/tools/ssh/delete_ssh_username.ex
defmodule EdgeAdminMcp.Tools.Ssh.DeleteSshUsername do
  @moduledoc "Delete an SSH username and all its associated public keys."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :ssh_username_id, {:required, :string}
  end

  @impl true
  def execute(%{ssh_username_id: id}, frame) do
    with {:ok, username} <- Ssh.get_ssh_username(id),
         {:ok, _} <- Ssh.delete_ssh_username(username) do
      {:reply, Response.text(Response.tool(), "SSH username #{id} deleted"), frame}
    else
      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "SSH username #{id} not found")), frame}

      {:error, reason} ->
        {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
    end
  end
end
