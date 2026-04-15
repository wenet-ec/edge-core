# edge_admin/lib/edge_admin_mcp/tools/self_updates/get_self_update_request.ex
defmodule EdgeAdminMcp.Tools.SelfUpdates.GetSelfUpdateRequest do
  @moduledoc "Get a self-update request by ID."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.SelfUpdates
  alias EdgeAdminMcp.Tools.SelfUpdates.SelfUpdateRequestData

  schema do
    field :request_id, {:required, :string}
  end

  @impl true
  def execute(%{request_id: id}, frame) do
    case SelfUpdates.get_self_update_request(id) do
      {:ok, request} ->
        {:reply, Response.json(Response.tool(), SelfUpdateRequestData.data(request)), frame}

      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "Self-update request #{id} not found")), frame}
    end
  end
end
