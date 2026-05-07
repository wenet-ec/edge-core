# edge_admin/lib/edge_admin_web/controllers/self_updates/self_update_request_json.ex
defmodule EdgeAdminWeb.Controllers.SelfUpdates.SelfUpdateRequestJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, requests: requests, meta: flop_meta}) do
    ResponseEnvelope.success(conn, requests, flop_meta)
  end

  def show(%{conn: conn, request: request}) do
    ResponseEnvelope.success(conn, request)
  end
end
