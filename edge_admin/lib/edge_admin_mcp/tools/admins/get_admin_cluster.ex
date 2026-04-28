# edge_admin/lib/edge_admin_mcp/tools/admins/get_admin_cluster.ex
defmodule EdgeAdminMcp.Tools.Admins.GetAdminCluster do
  @moduledoc "Get the admin cluster this admin belongs to — all peer admin instances, their assigned edge clusters, degraded flag, and current weak leader."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Admins.Metadata

  @impl true
  def title, do: "Get This Admin's Admin Cluster"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_admin_cluster()), frame}
  end
end
