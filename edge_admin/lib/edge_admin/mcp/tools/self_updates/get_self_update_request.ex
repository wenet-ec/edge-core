# edge_admin/lib/edge_admin/mcp/tools/self_updates/get_self_update_request.ex
defmodule EdgeAdmin.MCP.Tools.SelfUpdates.GetSelfUpdateRequest do
  @moduledoc "Get a self-update request by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.SelfUpdates.SelfUpdateRequestData
  alias EdgeAdmin.SelfUpdates

  schema do
    field :request_id, {:required, :string}
  end

  @impl true
  def execute(%{request_id: id}, frame) do
    case SelfUpdates.get_self_update_request(id) do
      {:ok, request} ->
        {:reply, Response.json(Response.tool(), SelfUpdateRequestData.data(request)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Self-update request #{id} not found"), frame}
    end
  end
end
