# edge_admin/lib/edge_admin_mcp/tools/nodes/change_node_cluster.ex
defmodule EdgeAdminMcp.Tools.Nodes.ChangeNodeCluster do
  @moduledoc """
  Move a node to a different cluster. The returned node reflects the saved
  assignment immediately; network connectivity may briefly reflect the previous
  assignment while it converges. Treat this as a destructive operation.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Naming
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.NodeView

  @max_length Naming.cluster_name_max_length()
  @regex Naming.cluster_name_regex()

  @impl true
  def title, do: "Move Node to Cluster"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => true}

  schema do
    field :node_id, {:required, :string}
    field :cluster_name, {:required, :string}, max_length: @max_length, regex: @regex
  end

  @impl true
  def execute(%{node_id: id, cluster_name: cluster_name}, frame) do
    case Nodes.get_node(id) do
      {:ok, node} ->
        case Nodes.change_node_cluster(node, %{"cluster_name" => cluster_name}) do
          {:ok, updated} ->
            {:reply, Response.json(Response.tool(), NodeView.render(updated)), frame}

          {:error, reason} ->
            {:reply, error_response(reason), frame}
        end

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{id} not found"), frame}
    end
  end
end
