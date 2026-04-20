# edge_admin/lib/edge_admin_mcp/tools/admins/list_edge_clusters.ex
defmodule EdgeAdminMcp.Tools.Admins.ListEdgeClusters do
  @moduledoc "List all edge clusters currently assigned to admin instances."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Admins.Metadata

  @impl true
  def title, do: "List Edge Clusters (Admin View)"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_edge_clusters()), frame}
  end
end
