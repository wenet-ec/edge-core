# edge_admin/lib/edge_admin_mcp/tools/nodes/delete_cluster.ex
defmodule EdgeAdminMcp.Tools.Nodes.DeleteCluster do
  @moduledoc """
  Accept deletion of an empty cluster. The cluster immediately stops appearing in
  normal reads; removal completes asynchronously. This action is irreversible.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes

  @impl true
  def title, do: "Delete Cluster"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => true}

  schema do
    field :cluster_name, {:required, :string}
  end

  @impl true
  def execute(%{cluster_name: name}, frame) do
    with {:ok, cluster} <- Nodes.get_cluster(name),
         {:ok, _} <- Nodes.delete_cluster(cluster) do
      {:reply, Response.json(Response.tool(), %{deletion: "accepted", name: name}), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Cluster #{name} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
