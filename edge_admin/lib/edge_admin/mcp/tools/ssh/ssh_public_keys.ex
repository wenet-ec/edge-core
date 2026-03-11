# edge_admin/lib/edge_admin/mcp/tools/ssh/ssh_public_keys.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.ListSshPublicKeys do
  @moduledoc "List SSH public keys. Filter by ssh_username_id to scope to a specific user."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
    field :ssh_username_id, :string
    field :key_name, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
      |> maybe_put("ssh_username_id", params[:ssh_username_id])
      |> maybe_put("key_name", params[:key_name])

    case Ssh.list_ssh_public_keys(query) do
      {:ok, {keys, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           ssh_public_keys: Enum.map(keys, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list SSH public keys: #{inspect(reason)}"), frame}
    end
  end

  defp format(k),
    do: %{
      id: k.id,
      key_name: k.key_name,
      public_key: k.public_key,
      ssh_username_id: k.ssh_username_id,
      inserted_at: k.inserted_at
    }

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end

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
