# edge_admin/lib/edge_admin_web/controllers/events/webhook_json.ex
defmodule EdgeAdminWeb.Controllers.Events.WebhookJSON do
  @moduledoc """
  JSON renderer for webhook responses.

  `secret` and `headers` are intentionally omitted — they're write-only at
  the API boundary. Encrypted at rest, never returned in any GET response.
  """

  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, webhooks: webhooks, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(webhooks, &data/1), flop_meta)
  end

  def show(%{conn: conn, webhook: webhook}) do
    ResponseEnvelope.success(conn, data(webhook))
  end

  defp data(%Webhook{} = webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      event_filters: webhook.event_filters,
      inserted_at: webhook.inserted_at,
      updated_at: webhook.updated_at
    }
  end
end
