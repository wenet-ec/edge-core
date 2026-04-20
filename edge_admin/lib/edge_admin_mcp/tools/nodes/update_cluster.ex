# edge_admin/lib/edge_admin_mcp/tools/nodes/update_cluster.ex
defmodule EdgeAdminMcp.Tools.Nodes.UpdateCluster do
  @moduledoc "Update a cluster's node_limit. Pass null to remove the limit."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.ClusterData

  @impl true
  def title, do: "Update Cluster"
  @impl true
  def annotations, do: %{"idempotentHint" => true}

  schema do
    field :cluster_name, {:required, :string}
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
            {:reply, error_response(reason), frame}
        end

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Cluster #{name} not found"), frame}
    end
  end
end
