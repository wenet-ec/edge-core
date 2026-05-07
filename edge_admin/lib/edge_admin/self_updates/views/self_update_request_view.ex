# edge_admin/lib/edge_admin/self_updates/views/self_update_request_view.ex
defmodule EdgeAdmin.SelfUpdates.Views.SelfUpdateRequestView do
  @moduledoc """
  Public-facing render for `SelfUpdateRequest` — the canonical map shape
  both REST and MCP serialize.
  """

  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  @spec render(SelfUpdateRequest.t()) :: map()
  def render(%SelfUpdateRequest{} = request) do
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
