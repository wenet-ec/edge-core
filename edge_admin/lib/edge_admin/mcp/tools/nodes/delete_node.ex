# edge_admin/lib/edge_admin/mcp/tools/nodes/delete_node.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.DeleteNode do
  @moduledoc "Remove a node from the system and its VPN mesh. The agent must re-enroll to reconnect."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :node_id, :string, required: true
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, _} <- Nodes.delete_node(node) do
      {:reply, Response.text(Response.tool(), "Node #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Node #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
