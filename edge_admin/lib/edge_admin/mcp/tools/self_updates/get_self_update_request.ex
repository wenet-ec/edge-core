# edge_admin/lib/edge_admin/mcp/tools/self_updates/get_self_update_request.ex
defmodule EdgeAdmin.MCP.Tools.SelfUpdates.GetSelfUpdateRequest do
  @moduledoc "Get a self-update request by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.SelfUpdates

  schema do
    field :request_id, :string, required: true
  end

  @impl true
  def execute(%{request_id: id}, frame) do
    case SelfUpdates.get_self_update_request(id) do
      {:ok, r} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: r.id,
           status: r.status,
           targeting: r.targeting,
           summary: r.summary,
           inserted_at: r.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Self-update request #{id} not found"), frame}
    end
  end
end
