# edge_admin/lib/edge_admin/mcp/tools/nodes/get_enrollment_key.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.GetEnrollmentKey do
  @moduledoc "Get an enrollment key by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :enrollment_key_id, :string, required: true
  end

  @impl true
  def execute(%{enrollment_key_id: id}, frame) do
    case Nodes.get_enrollment_key(id) do
      {:ok, k} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: k.id,
           key: k.key,
           cluster_name: k.cluster.name,
           uses_remaining: k.uses_remaining,
           expired_at: k.expired_at,
           last_used_at: k.last_used_at,
           inserted_at: k.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Enrollment key #{id} not found"), frame}
    end
  end
end
