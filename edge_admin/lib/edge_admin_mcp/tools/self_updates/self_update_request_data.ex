# edge_admin/lib/edge_admin_mcp/tools/self_updates/self_update_request_data.ex
defmodule EdgeAdminMcp.Tools.SelfUpdates.SelfUpdateRequestData do
  @moduledoc false

  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  def data(%SelfUpdateRequest{} = request) do
    %{
      id: request.id,
      targeting: request.targeting,
      status: request.status,
      summary: request.summary,
      inserted_at: request.inserted_at,
      updated_at: request.updated_at
    }
  end
end
