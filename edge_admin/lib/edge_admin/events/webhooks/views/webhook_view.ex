# edge_admin/lib/edge_admin/events/webhooks/views/webhook_view.ex
defmodule EdgeAdmin.Events.Webhooks.Views.WebhookView do
  @moduledoc """
  Public-facing render for `Webhook` — the canonical map shape both REST
  and MCP serialize. `secret` and `headers` are intentionally omitted —
  write-only at the API boundary, encrypted at rest.
  """

  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook

  @spec render(Webhook.t()) :: map()
  def render(%Webhook{} = webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      subscribed_events: webhook.subscribed_events,
      inserted_at: webhook.inserted_at,
      updated_at: webhook.updated_at
    }
  end
end
