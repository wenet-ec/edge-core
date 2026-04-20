# edge_admin/lib/edge_admin/event_broker/event_broker.ex
defmodule EdgeAdmin.EventBroker do
  @moduledoc """
  Publishes lifecycle events to a configured message broker.

  Core publishes and forgets — it has no knowledge of consumers.
  Publishing is fire-and-forget from the call site's perspective:
  errors are logged but never returned to the caller.

  ## Configuration

  Set `EVENT_BROKER_ENABLED=true` to enable. When disabled (default),
  all `publish/1` calls are immediate no-ops — no process is started,
  no connection is made.

  When enabled, `EVENT_BROKER_ADAPTER` and `EVENT_BROKER_URL` are required:
  - `nats` — NATS pub/sub; add `EVENT_BROKER_NATS_JETSTREAM=true` for durable log (recommended)
  - `kafka` — Kafka-compatible protocol (Redpanda recommended)
  - `rabbitmq` — RabbitMQ topic exchange; consumer queue durability is the consumer's choice
  - `redis` — Redis Pub/Sub; fire-and-forget, no durability or replay

  ## Usage

      # In business logic:
      EventBroker.enqueue(%EventBroker.Events.NodeRegistered{node: node})

  ## Event envelope

  Every published message follows the CloudEvents 1.0 spec:

      %{
        "specversion"     => "1.0",
        "id"              => uuid,
        "source"          => "https://github.com/wenet-ec/edge-core",
        "type"            => "node.registered",
        "time"            => iso8601,
        "datacontenttype" => "application/json",
        "corename"        => "prod-us",
        "data"            => %{...}
      }

  `corename` is a CloudEvents extension attribute identifying which core instance
  published the event. Defaults to `"default"` if `CORE_NAME` is not set.
  """

  alias EdgeAdmin.EventBroker.Events
  alias EdgeAdmin.EventBroker.Workers.PublishEventWorker

  require Logger

  @type event ::
          Events.NodeRegistered.t()
          | Events.NodeReregistered.t()
          | Events.NodeVersionChanged.t()
          | Events.NodeStatusChanged.t()
          | Events.NodeClusterChanged.t()
          | Events.NodeUpdateTriggered.t()
          | Events.NodeDeleted.t()
          | Events.ExecutionCreated.t()
          | Events.ExecutionSent.t()
          | Events.ExecutionCompleted.t()
          | Events.ExecutionCancelled.t()
          | Events.ExecutionExpired.t()
          | Events.SelfUpdateCreated.t()
          | Events.SelfUpdateCompleted.t()

  @doc """
  Returns `:ok` if the broker connection is healthy, `{:error, reason}` if not.
  Returns `:ok` immediately when the event broker is disabled.
  """
  @spec healthy?() :: :ok | {:error, String.t()}
  def healthy? do
    if Application.get_env(:edge_admin, :event_broker_enabled, false) do
      adapter().healthy?()
    else
      :ok
    end
  end

  @doc """
  Enqueues an event for async delivery via an Oban worker.

  Builds the envelope immediately — capturing the exact state at call time — then
  inserts an Oban job. The worker publishes to the broker and retries on failure,
  decoupling broker health from the caller entirely.

  Always returns `:ok`. No-op when the event broker is disabled.
  """
  @spec enqueue(event()) :: :ok
  def enqueue(event) do
    if Application.get_env(:edge_admin, :event_broker_enabled, false) do
      envelope = build_envelope(event)

      envelope
      |> PublishEventWorker.new()
      |> Oban.insert!()

      :ok
    else
      :ok
    end
  end

  @doc """
  Publishes a pre-built CloudEvents envelope directly to the broker.

  Called by `PublishEventWorker` — not intended for direct use in business logic.
  Returns `{:error, reason}` on failure so Oban can retry.
  """
  @spec publish_envelope(map()) :: :ok | {:error, term()}
  def publish_envelope(envelope) do
    mod = adapter()

    case mod.publish(envelope) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[EventBroker] Failed to publish #{envelope["type"]}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp adapter do
    case Application.get_env(:edge_admin, :event_broker_adapter) do
      :nats -> EdgeAdmin.EventBroker.Adapters.Nats
      :kafka -> EdgeAdmin.EventBroker.Adapters.Kafka
      :rabbitmq -> EdgeAdmin.EventBroker.Adapters.Rabbitmq
      :redis -> EdgeAdmin.EventBroker.Adapters.Redis
    end
  end

  defp build_envelope(event) do
    %{
      "specversion" => "1.0",
      "id" => Uniq.UUID.uuid4(),
      "source" => "https://github.com/wenet-ec/edge-core",
      "type" => Events.event_type(event),
      "time" => DateTime.to_iso8601(DateTime.utc_now()),
      "datacontenttype" => "application/json",
      "corename" => Application.get_env(:edge_admin, :core_name, "default"),
      "data" => Events.to_data(event)
    }
  end
end
