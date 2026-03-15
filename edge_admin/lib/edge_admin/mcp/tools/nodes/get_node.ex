# edge_admin/lib/edge_admin/mcp/tools/nodes/get_node.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.GetNode do
  @moduledoc "Get a node by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.NodeData
  alias EdgeAdmin.Nodes

  schema do
    field :node_id, :string, required: true
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    case Nodes.get_node(id) do
      {:ok, node} ->
        {:reply, Response.json(Response.tool(), NodeData.data(node)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Node #{id} not found"), frame}
    end
  end
end
