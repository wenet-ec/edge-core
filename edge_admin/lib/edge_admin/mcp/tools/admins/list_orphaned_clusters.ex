# edge_admin/lib/edge_admin/mcp/tools/admins/list_orphaned_clusters.ex
defmodule EdgeAdmin.MCP.Tools.Admins.ListOrphanedClusters do
  @moduledoc "List clusters with no assigned admin instance. These cannot receive commands until an admin picks them up."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), %{orphaned_clusters: Metadata.get_orphaned_clusters()}), frame}
  end
end
