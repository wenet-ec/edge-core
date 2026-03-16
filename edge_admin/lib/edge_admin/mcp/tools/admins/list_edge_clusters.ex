# edge_admin/lib/edge_admin/mcp/tools/admins/list_edge_clusters.ex
defmodule EdgeAdmin.MCP.Tools.Admins.ListEdgeClusters do
  @moduledoc "List all edge clusters currently assigned to admin instances."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), %{data: Metadata.get_edge_clusters()}), frame}
  end
end
