# edge_admin/lib/edge_admin_web/controllers/self_updates/self_update_request_json.ex
defmodule EdgeAdminWeb.Controllers.SelfUpdates.SelfUpdateRequestJSON do
  alias EdgeAdmin.SelfUpdates.Views.SelfUpdateRequestView
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, requests: requests, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(requests, &SelfUpdateRequestView.render/1), flop_meta)
  end

  def show(%{conn: conn, request: request}) do
    ResponseEnvelope.success(conn, SelfUpdateRequestView.render(request))
  end
end
