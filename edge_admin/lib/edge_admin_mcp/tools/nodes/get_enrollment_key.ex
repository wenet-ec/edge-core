# edge_admin/lib/edge_admin_mcp/tools/nodes/get_enrollment_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.GetEnrollmentKey do
  @moduledoc "Get an enrollment key by ID."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.EnrollmentKeyData

  schema do
    field :enrollment_key_id, {:required, :string}
  end

  @impl true
  def execute(%{enrollment_key_id: id}, frame) do
    case Nodes.get_enrollment_key(id) do
      {:ok, key} ->
        {:reply, Response.json(Response.tool(), EnrollmentKeyData.data(key)), frame}

      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "Enrollment key #{id} not found")), frame}
    end
  end
end
