# edge_admin/lib/edge_admin_mcp/tools/ssh/create_ssh_public_key.ex
defmodule EdgeAdminMcp.Tools.Ssh.CreateSshPublicKey do
  @moduledoc "Add an SSH public key to an existing SSH username. Key must be valid OpenSSH format."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh
  alias EdgeAdminMcp.Tools.Ssh.SshPublicKeyData

  schema do
    field :ssh_username_id, {:required, :string}
    field :public_key, {:required, :string}, min_length: 1
    field :key_name, :string, min_length: 1
  end

  @impl true
  def execute(params, frame) do
    case Ssh.get_ssh_username(params.ssh_username_id) do
      {:ok, ssh_username} ->
        attrs = put_if(%{"public_key" => params.public_key}, "key_name", params[:key_name])

        case Ssh.create_ssh_public_key(ssh_username, attrs) do
          {:ok, key} ->
            {:reply, Response.json(Response.tool(), SshPublicKeyData.data(key)), frame}

          {:error, reason} ->
            {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
        end

      {:error, :not_found} ->
        {:reply,
         Response.json(Response.tool(), tool_error(:not_found, "SSH username #{params.ssh_username_id} not found")),
         frame}
    end
  end
end
