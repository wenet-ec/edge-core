# edge_admin/lib/edge_admin/mcp/tools/nodes/aliases.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListAliases do
  @moduledoc "List DNS aliases. Aliases let you refer to nodes by a friendly name within the VPN mesh."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
  end

  @impl true
  def execute(params, frame) do
    case Nodes.list_aliases(%{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}) do
      {:ok, {aliases, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           aliases: Enum.map(aliases, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list aliases: #{inspect(reason)}"), frame}
    end
  end

  defp format(a),
    do: %{id: a.id, name: a.name, node_id: a.node_id, dns_hostname: a.dns_hostname, inserted_at: a.inserted_at}
end

defmodule EdgeAdmin.MCP.Tools.Nodes.GetAlias do
  @moduledoc "Get a DNS alias by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :alias_id, :string, required: true
  end

  @impl true
  def execute(%{alias_id: id}, frame) do
    case Nodes.get_alias(id) do
      {:ok, a} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: a.id,
           name: a.name,
           node_id: a.node_id,
           dns_hostname: a.dns_hostname,
           inserted_at: a.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Alias #{id} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Nodes.CreateAlias do
  @moduledoc "Create a DNS alias for a node. Resolves as <name>.<cluster-domain> within the VPN mesh."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :node_id, :string, required: true
    field :name, :string, required: true
  end

  @impl true
  def execute(%{node_id: node_id, name: name}, frame) do
    case Nodes.get_node(node_id) do
      {:ok, node} ->
        case Nodes.create_alias(node, %{"name" => name}) do
          {:ok, a} ->
            {:reply,
             Response.json(Response.tool(), %{id: a.id, name: a.name, node_id: a.node_id, dns_hostname: a.dns_hostname}),
             frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Failed to create alias: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Node #{node_id} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Nodes.DeleteAlias do
  @moduledoc "Delete a DNS alias."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :alias_id, :string, required: true
  end

  @impl true
  def execute(%{alias_id: id}, frame) do
    with {:ok, a} <- Nodes.get_alias(id),
         {:ok, _} <- Nodes.delete_alias(a) do
      {:reply, Response.text(Response.tool(), "Alias #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Alias #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
