# edge_admin/lib/edge_admin/event_broker/workers/publish_event_worker.ex
defmodule EdgeAdmin.EventBroker.Workers.PublishEventWorker do
  @moduledoc """
  Oban worker that publishes a pre-built CloudEvents envelope to the configured broker.

  Call sites build the envelope via `EventBroker.enqueue/1` immediately after the
  business logic succeeds. The worker picks it up asynchronously and handles retries
  on broker failure — decoupling broker health from the hot path entirely.

  The envelope is stored as-is in Oban job args (a plain JSON-serialisable map).
  No DB preloading happens here — the envelope is fully built at enqueue time so
  the event reflects the state at the moment it occurred, not when the worker runs.
  """

  use Oban.Worker,
    queue: :event_broker,
    max_attempts: 10

  alias EdgeAdmin.EventBroker

  @impl Oban.Worker
  def perform(%Oban.Job{args: envelope}) do
    EventBroker.publish_envelope(envelope)
  end
end
