# edge_admin/lib/edge_admin_mcp/tools/events/create_webhook.ex
defmodule EdgeAdminMcp.Tools.Events.CreateWebhook do
  @moduledoc """
  Create a webhook subscription. The destination URL is SSRF-checked at create time.
  Webhooks are immutable after create — to change any field, delete and recreate.

  - `secret` is the HMAC-SHA256 signing key (>= 32 bytes); it stays on our side and
    receivers verify the `X-Edge-Signature` header against their copy.
  - `headers` is a map of string→string headers stamped on every delivery
    (e.g. `Authorization: Bearer xoxb-...`).
  - `subscribed_events` is an explicit list of event-type strings — no wildcards.
    Each entry must be a known event type from the catalog. Capped at
    20 events per webhook; create additional webhooks if you need more.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Events.Webhooks
  alias EdgeAdminMcp.Tools.Events.WebhookData

  @impl true
  def title, do: "Create Webhook"
  @impl true
  def annotations, do: %{"destructiveHint" => false}

  schema do
    field :url, {:required, :string}
    field :secret, {:required, :string}, min_length: 32
    field :headers, :map
    field :subscribed_events, {:required, {:list, :string}}
  end

  @impl true
  def execute(params, frame) do
    attrs =
      put_if(
        %{
          "url" => params.url,
          "secret" => params.secret,
          "subscribed_events" => params.subscribed_events
        },
        "headers",
        params[:headers]
      )

    case Webhooks.create_webhook(attrs) do
      {:ok, webhook} ->
        {:reply, Response.json(Response.tool(), WebhookData.data(webhook)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
