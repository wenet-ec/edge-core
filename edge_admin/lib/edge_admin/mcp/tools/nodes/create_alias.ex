# edge_admin/lib/edge_admin/mcp/tools/nodes/create_alias.ex
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
