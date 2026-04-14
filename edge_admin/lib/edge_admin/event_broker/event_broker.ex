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
  - `nats_js` — NATS JetStream (recommended)
  - `kafka` — Kafka-compatible protocol (Redpanda recommended)

  ## Usage

      # In business logic:
      EventBroker.publish(%EventBroker.Events.NodeRegistered{node: node})

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
  Publishes an event to the configured broker.

  Always returns `:ok` — failures are logged, never raised.
  """
  @spec publish(event()) :: :ok
  def publish(event) do
    if Application.get_env(:edge_admin, :event_broker_enabled, false) do
      mod = adapter()
      envelope = build_envelope(event)

      case mod.publish(envelope) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("[EventBroker] Failed to publish #{envelope["type"]}: #{inspect(reason)}")

          :ok
      end
    else
      :ok
    end
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp adapter do
    case Application.get_env(:edge_admin, :event_broker_adapter) do
      :nats_js -> EdgeAdmin.EventBroker.Adapters.NatsJs
      :kafka -> EdgeAdmin.EventBroker.Adapters.Kafka
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
