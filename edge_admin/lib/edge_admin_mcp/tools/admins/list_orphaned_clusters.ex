# edge_admin/lib/edge_admin_mcp/tools/admins/list_orphaned_clusters.ex
defmodule EdgeAdminMcp.Tools.Admins.ListOrphanedClusters do
  @moduledoc """
  List edge clusters that currently have no assigned Admin instance.

  Orphaned clusters are not owned by an Admin and therefore cannot receive
  normal node health checks, reconciliation, or command delivery until the
  metadata coordinator assigns them again. This tool takes no parameters.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.AdminClustering.Metadata

  @impl true
  def title, do: "List Orphaned Clusters"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_orphaned_clusters()), frame}
  end
end
