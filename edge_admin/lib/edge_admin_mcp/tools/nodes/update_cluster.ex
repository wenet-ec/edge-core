# edge_admin/lib/edge_admin_mcp/tools/nodes/update_cluster.ex
defmodule EdgeAdminMcp.Tools.Nodes.UpdateCluster do
  @moduledoc """
  Update a cluster's `node_limit`.

  - **Omit `node_limit`** — leave the limit unchanged.
  - **Pass an integer** — set the limit to that value (must be ≥ current node count).
  - **Pass `null`** — remove the limit (unlimited).
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.ClusterView

  @impl true
  def title, do: "Update Cluster"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => true, "openWorldHint" => false}

  schema do
    field :cluster_name, {:required, :string}
    field :node_limit, :integer
  end

  @impl true
  def execute(%{cluster_name: name} = params, frame) do
    case Nodes.get_cluster(name) do
      {:ok, cluster} ->
        attrs = put_if_present(%{}, "node_limit", params, :node_limit)

        case Nodes.update_cluster(cluster, attrs) do
          {:ok, updated} ->
            {:reply, Response.json(Response.tool(), ClusterView.render(updated)), frame}

          {:error, reason} ->
            {:reply, error_response(reason), frame}
        end

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Cluster #{name} not found"), frame}
    end
  end
end
