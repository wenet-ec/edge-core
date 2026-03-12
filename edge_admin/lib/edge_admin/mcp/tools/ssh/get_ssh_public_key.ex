# edge_admin/lib/edge_admin/mcp/tools/ssh/get_ssh_public_key.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.GetSshPublicKey do
  @moduledoc "Get an SSH public key by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :ssh_public_key_id, :string, required: true
  end

  @impl true
  def execute(%{ssh_public_key_id: id}, frame) do
    case Ssh.get_ssh_public_key(id) do
      {:ok, k} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: k.id,
           key_name: k.key_name,
           public_key: k.public_key,
           ssh_username_id: k.ssh_username_id,
           inserted_at: k.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "SSH public key #{id} not found"), frame}
    end
  end
end
