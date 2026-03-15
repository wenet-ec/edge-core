# edge_admin/lib/edge_admin/mcp/tools/nodes/update_cluster.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.UpdateCluster do
  @moduledoc "Update a cluster's node_limit. Pass null to remove the limit."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.ClusterData
  alias EdgeAdmin.Nodes

  schema do
    field :cluster_name, :string, required: true
    field :node_limit, :integer
  end

  @impl true
  def execute(%{cluster_name: name} = params, frame) do
    case Nodes.get_cluster(name) do
      {:ok, cluster} ->
        case Nodes.update_cluster(cluster, %{"node_limit" => params[:node_limit]}) do
          {:ok, updated} ->
            {:reply, Response.json(Response.tool(), ClusterData.data(updated)), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Update failed: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Cluster #{name} not found"), frame}
    end
  end
end
