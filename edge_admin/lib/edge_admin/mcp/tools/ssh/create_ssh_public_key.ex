# edge_admin/lib/edge_admin/mcp/tools/ssh/create_ssh_public_key.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.CreateSshPublicKey do
  @moduledoc "Add an SSH public key to an existing SSH username. Key must be valid OpenSSH format."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :ssh_username_id, :string, required: true
    field :public_key, :string, required: true
    field :key_name, :string
  end

  @impl true
  def execute(params, frame) do
    case Ssh.get_ssh_username(params.ssh_username_id) do
      {:ok, ssh_username} ->
        attrs = maybe_put(%{"public_key" => params.public_key}, "key_name", params[:key_name])

        case Ssh.create_ssh_public_key(ssh_username, attrs) do
          {:ok, k} ->
            {:reply,
             Response.json(Response.tool(), %{
               id: k.id,
               key_name: k.key_name,
               public_key: k.public_key,
               ssh_username_id: k.ssh_username_id
             }), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Failed to add public key: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "SSH username #{params.ssh_username_id} not found"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
