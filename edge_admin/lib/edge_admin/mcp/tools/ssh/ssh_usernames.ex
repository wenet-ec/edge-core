# edge_admin/lib/edge_admin/mcp/tools/ssh/ssh_usernames.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.ListSshUsernames do
  @moduledoc "List SSH usernames. Filter by node_id to see credentials for a specific node."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
    field :node_id, :string
    field :username, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
      |> maybe_put("node_id", params[:node_id])
      |> maybe_put("username", params[:username])

    case Ssh.list_ssh_usernames(query) do
      {:ok, {usernames, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           ssh_usernames: Enum.map(usernames, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list SSH usernames: #{inspect(reason)}"), frame}
    end
  end

  defp format(u),
    do: %{id: u.id, username: u.username, has_password: u.has_password, node_id: u.node_id, inserted_at: u.inserted_at}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end

defmodule EdgeAdmin.MCP.Tools.Ssh.GetSshUsername do
  @moduledoc "Get an SSH username by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :ssh_username_id, :string, required: true
  end

  @impl true
  def execute(%{ssh_username_id: id}, frame) do
    case Ssh.get_ssh_username(id) do
      {:ok, u} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: u.id,
           username: u.username,
           has_password: u.has_password,
           node_id: u.node_id,
           inserted_at: u.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "SSH username #{id} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Ssh.CreateSshUsername do
  @moduledoc """
  Create an SSH username for a node. Optionally set a password and/or public keys.

  public_keys is a list of maps with `public_key` (required) and `key_name` (optional).
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Ssh

  schema do
    field :node_id, :string, required: true
    field :username, :string, required: true
    field :password, :string
    field :public_keys, {:array, :map}
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_node(params.node_id) do
      {:ok, node} ->
        attrs =
          %{"username" => params.username}
          |> maybe_put("password", params[:password])
          |> maybe_put("ssh_public_keys", params[:public_keys])

        case Ssh.create_ssh_username_with_keys(node, attrs) do
          {:ok, u} ->
            {:reply,
             Response.json(Response.tool(), %{
               id: u.id,
               username: u.username,
               has_password: u.has_password,
               node_id: u.node_id
             }), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Failed to create SSH username: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Node #{params.node_id} not found"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end

defmodule EdgeAdmin.MCP.Tools.Ssh.DeleteSshUsername do
  @moduledoc "Delete an SSH username and all its associated public keys."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :ssh_username_id, :string, required: true
  end

  @impl true
  def execute(%{ssh_username_id: id}, frame) do
    with {:ok, username} <- Ssh.get_ssh_username(id),
         {:ok, _} <- Ssh.delete_ssh_username(username) do
      {:reply, Response.text(Response.tool(), "SSH username #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "SSH username #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
