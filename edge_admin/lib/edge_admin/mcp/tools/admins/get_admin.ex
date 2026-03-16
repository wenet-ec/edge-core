# edge_admin/lib/edge_admin/mcp/tools/admins/get_admin.ex
defmodule EdgeAdmin.MCP.Tools.Admins.GetAdmin do
  @moduledoc "Get information about this admin instance — ID, version, assigned clusters, and peer count."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), %{data: Metadata.get_admin()}), frame}
  end
end
