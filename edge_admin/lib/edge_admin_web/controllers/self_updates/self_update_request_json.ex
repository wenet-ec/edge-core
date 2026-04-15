# edge_admin_web/controllers/self_updates/self_update_request_json.ex
defmodule EdgeAdminWeb.Controllers.SelfUpdates.SelfUpdateRequestJSON do
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, requests: requests, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(requests, &data/1), flop_meta)
  end

  def show(%{conn: conn, request: request}) do
    ResponseEnvelope.success(conn, data(request))
  end

  defp data(%SelfUpdateRequest{} = request) do
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
