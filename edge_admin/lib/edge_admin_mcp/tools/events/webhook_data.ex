# edge_admin/lib/edge_admin_mcp/tools/events/webhook_data.ex
defmodule EdgeAdminMcp.Tools.Events.WebhookData do
  @moduledoc false

  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook

  def data(%Webhook{} = webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      event_filters: webhook.event_filters,
      inserted_at: webhook.inserted_at,
      updated_at: webhook.updated_at
    }
  end
end
