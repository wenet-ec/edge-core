# edge_admin/lib/edge_admin_web/controllers/events/webhook_json.ex
defmodule EdgeAdminWeb.Controllers.Events.WebhookJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, webhooks: webhooks, meta: flop_meta}) do
    ResponseEnvelope.success(conn, webhooks, flop_meta)
  end

  def show(%{conn: conn, webhook: webhook}) do
    ResponseEnvelope.success(conn, webhook)
  end
end
