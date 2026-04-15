# edge_admin/lib/edge_admin_mcp/tools/ssh/get_ssh_username.ex
defmodule EdgeAdminMcp.Tools.Ssh.GetSshUsername do
  @moduledoc "Get an SSH username by ID."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh
  alias EdgeAdminMcp.Tools.Ssh.SshUsernameData

  schema do
    field :ssh_username_id, {:required, :string}
  end

  @impl true
  def execute(%{ssh_username_id: id}, frame) do
    case Ssh.get_ssh_username(id) do
      {:ok, username} ->
        {:reply, Response.json(Response.tool(), SshUsernameData.data(username)), frame}

      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "SSH username #{id} not found")), frame}
    end
  end
end
