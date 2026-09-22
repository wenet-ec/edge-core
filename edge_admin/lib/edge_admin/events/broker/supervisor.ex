# edge_admin/lib/edge_admin/events/broker/supervisor.ex
defmodule EdgeAdmin.Events.Broker.Supervisor do
  @moduledoc """
  Starts the event broker connection and adapter process.

  It starts the processes required by the selected adapter. The supervisor is
  only present when broker delivery is enabled.
  """

  use Supervisor

  alias EdgeAdmin.Events.Broker.Adapters.GooglePubsub
  alias EdgeAdmin.Events.Broker.Adapters.Nats

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

  defp build_children(:nats) do
    [
      Nats.connection_supervisor_spec(),
      Nats
    ]
  end

  defp build_children(:kafka) do
    [EdgeAdmin.Events.Broker.Adapters.Kafka]
  end

  defp build_children(:rabbitmq) do
    [EdgeAdmin.Events.Broker.Adapters.Rabbitmq]
  end

  defp build_children(:redis) do
    [EdgeAdmin.Events.Broker.Adapters.Redis]
  end

  defp build_children(:mqtt) do
    [EdgeAdmin.Events.Broker.Adapters.Mqtt]
  end

  defp build_children(:aws_sns) do
    [EdgeAdmin.Events.Broker.Adapters.AwsSns]
  end

  defp build_children(:google_pubsub) do
    config = Application.get_env(:edge_admin, :event_broker_google_pubsub, [])

    case Keyword.fetch!(config, :auth) do
      :goth ->
        [
          {Goth, name: GooglePubsub.goth_name()},
          GooglePubsub
        ]

      :none ->
        [GooglePubsub]
    end
  end
end
