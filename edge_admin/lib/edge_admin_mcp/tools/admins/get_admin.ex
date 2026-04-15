# edge_admin/lib/edge_admin_mcp/tools/admins/get_admin.ex
defmodule EdgeAdminMcp.Tools.Admins.GetAdmin do
  @moduledoc "Get information about this admin instance — ID, version, assigned clusters, and peer count."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_admin()), frame}
  end
end
