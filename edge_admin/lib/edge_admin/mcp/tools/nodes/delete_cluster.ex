# edge_admin/lib/edge_admin/mcp/tools/nodes/delete_cluster.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.DeleteCluster do
  @moduledoc "Delete a cluster and its VPN network. All nodes lose connectivity. Irreversible."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :cluster_name, :string, required: true
  end

  @impl true
  def execute(%{cluster_name: name}, frame) do
    with {:ok, cluster} <- Nodes.get_cluster(name),
         {:ok, _} <- Nodes.delete_cluster(cluster) do
      {:reply, Response.text(Response.tool(), "Cluster #{name} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Cluster #{name} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
