# edge_admin/lib/edge_admin_web/controllers/events/webhook_json.ex
defmodule EdgeAdminWeb.Controllers.Events.WebhookJSON do
  alias EdgeAdmin.Events.Webhooks.Views.WebhookView
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, webhooks: webhooks, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(webhooks, &WebhookView.render/1), flop_meta)
  end

  def show(%{conn: conn, webhook: webhook}) do
    ResponseEnvelope.success(conn, WebhookView.render(webhook))
  end
end
