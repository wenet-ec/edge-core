# edge_admin/lib/edge_admin/events/broker/adapters/aws_sns.ex
defmodule EdgeAdmin.Events.Broker.Adapters.AwsSns do
  @moduledoc """
  AWS SNS adapter for the event broker.

  Publishes CloudEvents to pre-provisioned SNS topics. Event type and core name
  are sent as message attributes for subscription filtering; the body remains
  the complete CloudEvents envelope. Topic provisioning and AWS credentials are
  deployment responsibilities.

  ## Durability

  SNS itself does not persist messages — once delivered to subscribers (or
  delivery is exhausted), the message is gone. Subscribers buy durability by
  being SQS queues, Lambda functions, or other receivers with their own
  storage. Edge Core's responsibility ends at the publish call.

  Authentication uses the standard AWS credential chain. Region, topic prefix,
  and optional endpoint overrides come from deployment configuration.
  """

  @behaviour EdgeAdmin.Events.Broker.Adapter

  use GenServer

  alias EdgeAdmin.Events.Broker.Adapter
  alias EdgeAdmin.Events.Broker.TopicRouting

  require Logger

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl Adapter
  def healthy? do
    case GenServer.call(__MODULE__, :healthy?) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "AWS SNS adapter not started"}
  end

  @impl Adapter
  def publish(envelope) do
    GenServer.call(__MODULE__, {:publish, envelope})
  rescue
    _ -> {:error, "AWS SNS adapter not started"}
  end

  @impl GenServer
  def init([]) do
    config = Application.get_env(:edge_admin, :event_broker_aws_sns, [])
    prefix = Keyword.fetch!(config, :topic_arn_prefix)

    Logger.info(
      "[EventBroker.AwsSns] Configured for region=#{Keyword.fetch!(config, :region)} " <>
        "topic_arn_prefix=#{prefix}" <>
        if(Keyword.get(config, :endpoint_url),
          do: " endpoint_url=#{Keyword.get(config, :endpoint_url)}",
          else: ""
        )
    )

    {:ok, %{topic_arn_prefix: prefix}}
  end

  # SNS is HTTP-stateless — no connection to liveness-check. We perform a
  # cheap ListTopics call as a probe; success means credentials and network
  # both work end-to-end.
  @impl GenServer
  def handle_call(:healthy?, _from, state) do
    topic_arn = state.topic_arn_prefix <> "edge-nodes-events"

    case ExAws.request(ExAws.SNS.get_topic_attributes(topic_arn)) do
      {:ok, _} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, "SNS topic unavailable: #{inspect(reason)}"}, state}
    end
  end

  def handle_call({:publish, envelope}, _from, state) do
    topic_arn = state.topic_arn_prefix <> TopicRouting.topic_for(envelope["type"])
    payload = JSON.encode!(envelope)

    # Each attribute is a map per ex_aws_sns's @type message_attribute spec:
    #   %{name, data_type, value: {:string | :binary, value}}
    # We promote `type` and `corename` to message attributes so subscription
    # filter policies can route without parsing the body.
    message_attributes = [
      %{name: "type", data_type: :string, value: {:string, envelope["type"]}},
      %{name: "corename", data_type: :string, value: {:string, envelope["corename"]}}
    ]

    operation =
      ExAws.SNS.publish(payload,
        topic_arn: topic_arn,
        message_attributes: message_attributes
      )

    case ExAws.request(operation) do
      {:ok, _result} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, inspect(reason)}, state}
    end
  end
end
