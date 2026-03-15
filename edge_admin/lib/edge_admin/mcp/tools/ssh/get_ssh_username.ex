# edge_admin/lib/edge_admin/mcp/tools/ssh/get_ssh_username.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.GetSshUsername do
  @moduledoc "Get an SSH username by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Ssh.SshUsernameData
  alias EdgeAdmin.Ssh

  schema do
    field :ssh_username_id, :string, required: true
  end

  @impl true
  def execute(%{ssh_username_id: id}, frame) do
    case Ssh.get_ssh_username(id) do
      {:ok, username} ->
        {:reply, Response.json(Response.tool(), SshUsernameData.data(username)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "SSH username #{id} not found"), frame}
    end
  end
end
