# edge_admin/lib/edge_admin_mcp/tools/events/webhook_data.ex
defmodule EdgeAdminMcp.Tools.Events.WebhookData do
  @moduledoc false

  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook

  def data(%Webhook{} = webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      subscribed_events: webhook.subscribed_events,
      inserted_at: webhook.inserted_at,
      updated_at: webhook.updated_at
    }
  end
end
