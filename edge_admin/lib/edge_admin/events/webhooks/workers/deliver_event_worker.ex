# edge_admin/lib/edge_admin/events/webhooks/workers/deliver_event_worker.ex
defmodule EdgeAdmin.Events.Webhooks.Workers.DeliverEventWorker do
  @moduledoc """
  Oban worker that delivers one (webhook × envelope) pair via HTTP.

  Inserted by `EdgeAdmin.Events.Webhooks.fan_out/1` — one job per matching
  webhook per published event. Args carry the webhook id (so we re-fetch the
  encrypted secret/headers on each attempt) plus the full envelope (so the
  delivered payload reflects the moment of publish, not delivery time).

  ## Retry budget

  Per-job `max_attempts` is set at insert time from `WEBHOOK_MAX_ATTEMPTS`
  (default 3). The static `max_attempts: 3` declared on `use Oban.Worker` is
  a fallback for direct callers; the fan-out path always sets it explicitly.

  ## Delivery TTL

  Same gate as the broker worker — `Oban.Job.inserted_at` against
  `EVENT_DELIVERY_MAX_AGE_SECONDS` (default 3600). Expired jobs are
  cancelled — never delivered.

  ## Retry classification

  Recoverable HTTP errors (408 / 429 / 503) and network errors return
  `{:error, _}` so Oban schedules a retry with exponential backoff until the
  job's `max_attempts` is exhausted, then discards. Terminal HTTP errors
  (other 4xx / 5xx) return `{:cancel, _}` so Oban skips remaining retries.
  """

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 3

  alias EdgeAdmin.Events.Webhooks

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, inserted_at: inserted_at}) do
    %{"webhook_id" => webhook_id, "envelope" => envelope} = args
    max_age = Application.get_env(:edge_admin, :event_delivery_max_age_seconds, 3600)
    age_seconds = DateTime.diff(DateTime.utc_now(), inserted_at, :second)

    cond do
      max_age == 0 ->
        Webhooks.deliver_event(webhook_id, envelope)

      age_seconds > max_age ->
        Logger.warning(
          "[Webhook] dropping expired delivery (age=#{age_seconds}s, max=#{max_age}s)",
          webhook_id: webhook_id,
          event_type: envelope["type"]
        )

        {:cancel, {:expired, age_seconds: age_seconds, max_age_seconds: max_age}}

      true ->
        Webhooks.deliver_event(webhook_id, envelope)
    end
  end
end
