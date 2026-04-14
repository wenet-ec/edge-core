# edge_admin/lib/edge_admin_mcp/tools/ssh/create_ssh_username.ex
defmodule EdgeAdminMcp.Tools.Ssh.CreateSshUsername do
  @moduledoc """
  Create an SSH username for a node. Optionally set a password and/or public keys.

  public_keys is a list of maps with `public_key` (required) and `key_name` (optional).
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Ssh
  alias EdgeAdminMcp.Tools.Ssh.SshUsernameData

  schema do
    field :node_id, {:required, :string}
    field :username, {:required, :string}, min_length: 1
    field :password, :string, min_length: 1
    field :public_keys, {:list, :map}
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_node(params.node_id) do
      {:ok, node} ->
        attrs =
          %{"username" => params.username}
          |> put_if("password", params[:password])
          |> put_if("ssh_public_keys", params[:public_keys])

        case Ssh.create_ssh_username_with_keys(node, attrs) do
          {:ok, username} ->
            {:reply, Response.json(Response.tool(), SshUsernameData.data(username)), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Failed to create SSH username: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Node #{params.node_id} not found"), frame}
    end
  end

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)
end
