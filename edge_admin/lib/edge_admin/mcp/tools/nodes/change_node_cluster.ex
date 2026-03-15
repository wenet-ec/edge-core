# edge_admin/lib/edge_admin/mcp/tools/nodes/change_node_cluster.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ChangeNodeCluster do
  @moduledoc "Move a node to a different cluster. The node is removed from its current VPN network and added to the new one."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.NodeData
  alias EdgeAdmin.Nodes

  schema do
    field :node_id, :string, required: true
    field :cluster_name, :string, required: true
  end

  @impl true
  def execute(%{node_id: id, cluster_name: cluster_name}, frame) do
    case Nodes.get_node(id) do
      {:ok, node} ->
        case Nodes.change_node_cluster(node, %{"cluster_name" => cluster_name}) do
          {:ok, updated} ->
            {:reply, Response.json(Response.tool(), NodeData.data(updated)), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Failed to change cluster: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Node #{id} not found"), frame}
    end
  end
end
