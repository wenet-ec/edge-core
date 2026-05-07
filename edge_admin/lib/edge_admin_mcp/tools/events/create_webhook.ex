# edge_admin/lib/edge_admin_mcp/tools/events/create_webhook.ex
defmodule EdgeAdminMcp.Tools.Events.CreateWebhook do
  @moduledoc """
  Create a webhook subscription. Webhooks are immutable after create — to
  change any field, delete and recreate.

  - `url` — required absolute http(s) URL, max 2048 chars. SSRF-checked at
    create time: loopback, RFC1918, link-local, and cloud-metadata IPs are
    rejected unless `WEBHOOK_ALLOW_PRIVATE_IPS=true` is set on the admin
    process.
  - `secret` — required HMAC-SHA256 signing key, 32–256 chars. Stays on
    the server. Receivers verify the `X-Edge-Signature` header against
    their stored copy.
  - `headers` — optional map of string→string headers stamped on every
    delivery (e.g. `Authorization: Bearer xoxb-...`). Up to 20 entries;
    each value up to 4096 chars.
  - `subscribed_events` — required explicit list of event-type strings,
    1–20 items, each ≤256 chars. No wildcards. Each entry must be a known
    event type from the catalog at `/asyncdoc`; unknown values are
    rejected at create time.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Events.Webhooks
  alias EdgeAdminMcp.Tools.Events.WebhookData

  @impl true
  def title, do: "Create Webhook"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :url, {:required, :string}, max_length: 2048, regex: ~r{^https?://.+}
    field :secret, {:required, :string}, min_length: 32, max_length: 256
    field :headers, {:map, :string, :string}
    field :subscribed_events, {:required, {:list, {:string, max: 256}}}, min: 1, max: 20
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
