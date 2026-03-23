# edge_admin/lib/edge_admin/mcp/tools/nodes/get_cluster.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.GetCluster do
  @moduledoc "Get a cluster by name."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.ClusterData
  alias EdgeAdmin.Nodes

  schema do
    field :cluster_name, {:required, :string}
  end

  @impl true
  def execute(%{cluster_name: name}, frame) do
    case Nodes.get_cluster(name) do
      {:ok, cluster} ->
        {:reply, Response.json(Response.tool(), ClusterData.data(cluster)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Cluster #{name} not found"), frame}
    end
  end
end
