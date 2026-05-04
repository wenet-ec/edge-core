# edge_admin/lib/edge_admin/events/broker/workers/publish_event_worker.ex
defmodule EdgeAdmin.Events.Broker.Workers.PublishEventWorker do
  @moduledoc """
  Oban worker that publishes a pre-built CloudEvents envelope to the configured broker.

  Call sites build the envelope via `EdgeAdmin.Events.publish/1` immediately after
  the business logic succeeds; that fans out to `EdgeAdmin.Events.Broker.enqueue/1`,
  which inserts this worker. The worker picks up asynchronously and handles retries
  on broker failure — decoupling broker health from the hot path entirely.

  The envelope is stored as-is in Oban job args (a plain JSON-serialisable map).
  No DB preloading happens here — the envelope is fully built at enqueue time so
  the event reflects the state at the moment it occurred, not when the worker runs.

  ## Delivery TTL

  Each job is checked against `:event_delivery_max_age_seconds` (env var
  `EVENT_DELIVERY_MAX_AGE_SECONDS`, default 3600) at the start of `perform/1`.
  If the job has been queued longer than the TTL it is cancelled — never published.
  This caps producer-side resource usage when the broker is unreachable for hours;
  consumers can still tell stale events from the envelope `time` field if they
  ever receive them, but we don't keep retrying delivery indefinitely.

  Set `EVENT_DELIVERY_MAX_AGE_SECONDS=0` to disable the TTL and rely solely on
  `max_attempts` for retry exhaustion.
  """

  use Oban.Worker,
    queue: :event_broker,
    max_attempts: 6

  alias EdgeAdmin.Events.Broker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: envelope, inserted_at: inserted_at}) do
    max_age = Application.get_env(:edge_admin, :event_delivery_max_age_seconds, 3600)
    age_seconds = DateTime.diff(DateTime.utc_now(), inserted_at, :second)

    cond do
      max_age == 0 ->
        Broker.publish_envelope(envelope)

      age_seconds > max_age ->
        Logger.warning(
          "[EventBroker] Dropping expired event #{envelope["type"]} " <>
            "(age=#{age_seconds}s, max=#{max_age}s)"
        )

        {:cancel, {:expired, age_seconds: age_seconds, max_age_seconds: max_age}}

      true ->
        Broker.publish_envelope(envelope)
    end
  end
end
