# edge_admin/lib/edge_admin/event_broker/supervisor.ex
defmodule EdgeAdmin.EventBroker.Supervisor do
  @moduledoc """
  Starts the event broker connection and adapter process.

  Only added to the supervision tree when `EVENT_BROKER_ENABLED=true`.
  If disabled, this supervisor is never started and the app is unaffected.

  ## Children (NATS adapter)

    1. `Gnat.ConnectionSupervisor` — maintains a named NATS connection with
       automatic reconnect.
    2. `EdgeAdmin.EventBroker.Adapters.Nats` — GenServer that optionally ensures
       JetStream streams exist on startup (when `EVENT_BROKER_NATS_JETSTREAM=true`).

  ## Children (Kafka adapter)

    1. `EdgeAdmin.EventBroker.Adapters.Kafka` — GenServer that starts the
       `:brod` client and per-topic producers.

  ## Children (RabbitMQ adapter)

    1. `EdgeAdmin.EventBroker.Adapters.Rabbitmq` — GenServer that opens an
       AMQP connection + channel, declares the topic exchange, and monitors
       the connection for auto-reconnect.

  ## Children (Redis adapter)

    1. `EdgeAdmin.EventBroker.Adapters.Redis` — GenServer that opens a Redix
       connection and publishes events via Redis Pub/Sub (`PUBLISH`).

  ## Children (MQTT adapter)

    1. `EdgeAdmin.EventBroker.Adapters.Mqtt` — GenServer that opens an `emqtt`
       client connection and publishes events to topic = event type.

  ## Children (AWS SNS adapter)

    1. `EdgeAdmin.EventBroker.Adapters.AwsSns` — GenServer that holds publish
       config. SNS is HTTPS-stateless, no persistent connection — every
       publish is an `ex_aws` request.
  """

  use Supervisor

  alias EdgeAdmin.EventBroker.Adapters.Nats

  require Logger

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl Supervisor
  def init([]) do
    adapter = Application.get_env(:edge_admin, :event_broker_adapter)
    children = build_children(adapter)
    Logger.info("[EventBroker] Starting with adapter: #{inspect(adapter)}")
    Supervisor.init(children, strategy: :one_for_one)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_children(:nats) do
    [
      Nats.connection_supervisor_spec(),
      Nats
    ]
  end

  defp build_children(:kafka) do
    [EdgeAdmin.EventBroker.Adapters.Kafka]
  end

  defp build_children(:rabbitmq) do
    [EdgeAdmin.EventBroker.Adapters.Rabbitmq]
  end

  defp build_children(:redis) do
    [EdgeAdmin.EventBroker.Adapters.Redis]
  end

  defp build_children(:mqtt) do
    [EdgeAdmin.EventBroker.Adapters.Mqtt]
  end

  defp build_children(:aws_sns) do
    [EdgeAdmin.EventBroker.Adapters.AwsSns]
  end
end
