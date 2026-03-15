# edge_admin/lib/edge_admin/mcp/tools/nodes/get_enrollment_key.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.GetEnrollmentKey do
  @moduledoc "Get an enrollment key by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.EnrollmentKeyData
  alias EdgeAdmin.Nodes

  schema do
    field :enrollment_key_id, :string, required: true
  end

  @impl true
  def execute(%{enrollment_key_id: id}, frame) do
    case Nodes.get_enrollment_key(id) do
      {:ok, key} ->
        {:reply, Response.json(Response.tool(), EnrollmentKeyData.data(key)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Enrollment key #{id} not found"), frame}
    end
  end
end
