# edge_admin/lib/edge_admin/events/webhooks/delivery.ex
defmodule EdgeAdmin.Events.Webhooks.Delivery do
  @moduledoc """
  Builds and sends a single HTTP webhook request.

  Responsibilities:

    1. JSON-encode the envelope (always — wire format is structured CloudEvents)
    2. HMAC-SHA256 sign the body with the webhook's `secret`, surface as `X-Edge-Signature`
    3. Stamp configured `headers` on the request as-is
    4. POST via Req with a sane timeout
    5. Classify the response — `:ok | {:recoverable, reason} | {:terminal, reason}`

  Retry classification:

    - 2xx                       → :ok
    - 408, 429, 503             → recoverable (retry)
    - other 4xx / 5xx           → terminal (don't retry — receiver said no)
    - econnrefused, timeout, …  → recoverable
    - any other Req error       → recoverable (treat unfamiliar transport
                                  errors as transient; one retry is cheaper
                                  than mis-classifying a real bug)

  `Webhooks.do_deliver/2` maps `:recoverable → {:error, reason}` so Oban
  schedules a retry with its built-in exponential backoff (no `:snooze`
  involved); `:terminal → {:cancel, …}` so Oban skips remaining retries.
  """

  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook

  require Logger

  @signature_header "x-edge-signature"
  @content_type "application/cloudevents+json"
  @default_timeout_ms 10_000

  @type result :: :ok | {:recoverable, term()} | {:terminal, term()}

  @doc """
  Sends an envelope to the webhook's URL. Returns `:ok | {:recoverable, ...} |
  {:terminal, ...}`.
  """
  @spec send(Webhook.t(), map()) :: result()
  def send(%Webhook{} = webhook, envelope) when is_map(envelope) do
    body = Jason.encode!(envelope)
    headers = build_headers(webhook, body)

    webhook.url
    |> Req.post(body: body, headers: headers, receive_timeout: @default_timeout_ms)
    |> classify(webhook, envelope)
  end

  # ---------------------------------------------------------------------------
  # Headers / signing
  # ---------------------------------------------------------------------------

  defp build_headers(%Webhook{secret: secret, headers: extra}, body) do
    signature = sign(secret, body)

    base = [
      {"content-type", @content_type},
      {@signature_header, "sha256=" <> signature}
    ]

    base ++ Enum.map(extra || %{}, fn {k, v} -> {k, v} end)
  end

  defp sign(secret, body) when is_binary(secret) and is_binary(body) do
    :hmac |> :crypto.mac(:sha256, secret, body) |> Base.encode16(case: :lower)
  end

  # ---------------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------------

  defp classify({:ok, %Req.Response{status: status}}, _webhook, _envelope) when status in 200..299 do
    :ok
  end

  defp classify({:ok, %Req.Response{status: status} = resp}, webhook, envelope) when status in [408, 429, 503] do
    log_failure(webhook, envelope, "recoverable HTTP #{status}", resp)
    {:recoverable, {:http_status, status}}
  end

  defp classify({:ok, %Req.Response{status: status} = resp}, webhook, envelope) do
    log_failure(webhook, envelope, "terminal HTTP #{status}", resp)
    {:terminal, {:http_status, status}}
  end

  defp classify({:error, %{reason: reason}}, webhook, envelope)
       when reason in [:timeout, :econnrefused, :closed, :nxdomain, :ehostunreach] do
    log_failure(webhook, envelope, "recoverable network error: #{inspect(reason)}", nil)
    {:recoverable, {:network, reason}}
  end

  defp classify({:error, error}, webhook, envelope) do
    # Anything else from Req — wrap as recoverable. Network is volatile; we'd
    # rather retry once than treat an unfamiliar transport error as terminal.
    log_failure(webhook, envelope, "recoverable transport error: #{inspect(error)}", nil)
    {:recoverable, {:transport, error}}
  end

  defp log_failure(webhook, envelope, summary, _resp) do
    Logger.warning(
      "[Webhook] delivery failed: #{summary}",
      webhook_id: webhook.id,
      url: webhook.url,
      event_id: envelope["id"],
      event_type: envelope["type"]
    )
  end
end
