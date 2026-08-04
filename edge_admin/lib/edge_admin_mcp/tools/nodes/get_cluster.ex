# edge_admin/lib/edge_admin_mcp/tools/nodes/get_cluster.ex
defmodule EdgeAdminMcp.Tools.Nodes.GetCluster do
  @moduledoc """
  Get an edge cluster by name.

  - `cluster_name` — required. Cluster names are the canonical cluster
    identifier and are also used to locate the corresponding VPN network.

  The response includes the cluster's address ranges, node limit, and current
  lifecycle metadata.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.ClusterView

  @impl true
  def title, do: "Get Cluster"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :cluster_name, {:required, :string}
  end

  @impl true
  def execute(%{cluster_name: name}, frame) do
    case Nodes.get_cluster(name) do
      {:ok, cluster} ->
        {:reply, Response.json(Response.tool(), ClusterView.render(cluster)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Cluster #{name} not found"), frame}
    end
  end
end
