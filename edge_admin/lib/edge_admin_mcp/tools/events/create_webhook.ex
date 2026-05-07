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

  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Events.Webhooks
  alias EdgeAdmin.Events.Webhooks.Limits

  @max_url_length Limits.max_url_length()
  @min_secret_bytes Limits.min_secret_bytes()
  @max_secret_bytes Limits.max_secret_bytes()
  @max_headers Limits.max_headers()
  @max_header_value_length Limits.max_header_value_length()
  @min_subscribed_events Limits.min_subscribed_events()
  @max_subscribed_events Limits.max_subscribed_events()
  @max_event_type_length Limits.max_event_type_length()

  @impl true
  def title, do: "Create Webhook"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :url, {:required, :string}, max_length: @max_url_length, regex: ~r{^https?://.+}
    field :secret, {:required, :string}, min_length: @min_secret_bytes, max_length: @max_secret_bytes
    field :headers, {:custom, {__MODULE__, :validate_headers}}

    field :subscribed_events, {:required, {:list, {:custom, {__MODULE__, :validate_event_type}}}},
      min: @min_subscribed_events,
      max: @max_subscribed_events
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
        {:reply, Response.json(Response.tool(), webhook), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end

  @doc """
  Validates the `headers` map: string→string, at most #{@max_headers}
  entries, each value ≤#{@max_header_value_length} chars. Returns the
  original map on success.
  """
  @spec validate_headers(term()) :: {:ok, map()} | {:error, String.t(), keyword()}
  def validate_headers(value) when is_map(value) do
    cond do
      map_size(value) > @max_headers ->
        {:error, "headers map must have at most %{max} entries, got %{count}", max: @max_headers,
         count: map_size(value)}

      not Enum.all?(value, fn {k, v} -> is_binary(k) and is_binary(v) end) ->
        {:error, "headers must be a string→string map", []}

      Enum.any?(value, fn {_k, v} -> String.length(v) > @max_header_value_length end) ->
        {:error, "each header value must be at most %{max} characters", max: @max_header_value_length}

      true ->
        {:ok, value}
    end
  end

  def validate_headers(_), do: {:error, "headers must be a map", []}

  @doc """
  Validates a single event type string against `Catalog.all_event_types/0`,
  also enforcing the per-string length cap. Returns the original string on
  success.
  """
  @spec validate_event_type(term()) :: {:ok, String.t()} | {:error, String.t(), keyword()}
  def validate_event_type(value) when is_binary(value) do
    cond do
      String.length(value) > @max_event_type_length ->
        {:error, "event type must be at most %{max} characters", max: @max_event_type_length}

      value in Catalog.all_event_types() ->
        {:ok, value}

      true ->
        {:error, "%{value} is not a known event type — see /asyncdoc for the catalog", value: value}
    end
  end

  def validate_event_type(_), do: {:error, "event type must be a string", []}
end
