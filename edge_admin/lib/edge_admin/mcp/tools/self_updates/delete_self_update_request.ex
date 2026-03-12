# edge_admin/lib/edge_admin/mcp/tools/self_updates/delete_self_update_request.ex
defmodule EdgeAdmin.MCP.Tools.SelfUpdates.DeleteSelfUpdateRequest do
  @moduledoc "Delete a self-update request. Only completed requests can be deleted."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.SelfUpdates

  schema do
    field :request_id, :string, required: true
  end

  @impl true
  def execute(%{request_id: id}, frame) do
    with {:ok, request} <- SelfUpdates.get_self_update_request(id),
         {:ok, _} <- SelfUpdates.delete_self_update_request(request) do
      {:reply, Response.text(Response.tool(), "Self-update request #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Self-update request #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
