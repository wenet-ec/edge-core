# edge_admin/lib/edge_admin_mcp/tools/admins/get_admin_cluster.ex
defmodule EdgeAdminMcp.Tools.Admins.GetAdminCluster do
  @moduledoc "Get the admin cluster status — all peer admin instances, their assigned edge clusters, degraded flag, and current weak leader."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_admin_cluster()), frame}
  end
end
