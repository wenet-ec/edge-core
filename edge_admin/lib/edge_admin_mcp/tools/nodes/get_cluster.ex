# edge_admin/lib/edge_admin_mcp/tools/nodes/get_cluster.ex
defmodule EdgeAdminMcp.Tools.Nodes.GetCluster do
  @moduledoc "Get a cluster by name."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.ClusterData

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
