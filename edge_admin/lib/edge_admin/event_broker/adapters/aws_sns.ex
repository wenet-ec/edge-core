# edge_admin/lib/edge_admin/event_broker/adapters/aws_sns.ex
defmodule EdgeAdmin.EventBroker.Adapters.AwsSns do
  @moduledoc """
  AWS SNS adapter for the event broker.

  Publishes events to AWS Simple Notification Service via the `ex_aws_sns`
  client. SNS is a managed service with no on-prem distribution — production
  always points at real AWS. For local development and CI/staging, the adapter
  works against [LocalStack](https://localstack.cloud) by setting
  `EVENT_BROKER_AWS_SNS_ENDPOINT_URL`.

  ## Topics

  Three SNS topics by domain (matches the Kafka adapter convention):

      edge-nodes-events           partition: n/a (SNS does not partition)
      edge-commands-events
      edge-self-updates-events

  Topics must be pre-provisioned in the AWS account (Console / CLI / Terraform);
  the adapter does not create them. The full topic ARN is constructed from
  `EVENT_BROKER_AWS_SNS_TOPIC_ARN_PREFIX` + the suffix above.

  ## Routing / filtering — message attributes, not topic patterns

  SNS has no topic-name wildcards. Subscribers filter via *filter policies* on
  their subscriptions, evaluated against *message attributes* (key/value pairs
  that travel alongside the body). The adapter publishes two attributes:

      type      = "edge.node.status_changed"
      corename  = "prod-us"

  Subscribers can write filter policies like:

      {"type":     [{"prefix": "edge.node."}]}              # all node events
      {"type":     ["edge.command_execution.completed"]}    # specific event type
      {"corename": ["prod-us"]}                              # filter by core instance

  The body remains the full CloudEvents envelope JSON regardless — body and
  attributes carry the same routing fields, so consumers reading the body
  do not need to be aware of attributes.

  ## Durability

  SNS itself does not persist messages — once delivered to subscribers (or
  delivery is exhausted), the message is gone. Subscribers buy durability by
  being SQS queues, Lambda functions, or other receivers with their own
  storage. Edge Core's responsibility ends at the publish call.

  ## Auth — standard AWS credential chain (resolved by ex_aws)

  ex_aws walks the AWS standard credential chain:

  1. Environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
     optional `AWS_SESSION_TOKEN` (for STS / assumed roles).
  2. Shared credentials file (`~/.aws/credentials`).
  3. EC2 instance metadata service / ECS task role / Pod identity (when
     running on AWS infrastructure).

  No adapter-specific auth env vars — IAM credentials follow AWS conventions.

  ## Configuration (set in runtime.exs from env vars)

      config :ex_aws, :sns,
        region: "us-east-1"
        # + optional scheme/host/port overrides for LocalStack

      config :edge_admin, :event_broker_aws_sns,
        region: "us-east-1",
        topic_arn_prefix: "arn:aws:sns:us-east-1:123456789012:",
        endpoint_url: nil   # set only for LocalStack / non-AWS endpoints

  Controlled by env vars:
  - `EVENT_BROKER_AWS_SNS_REGION` — AWS region (e.g. `us-east-1`)
  - `EVENT_BROKER_AWS_SNS_TOPIC_ARN_PREFIX` — full ARN prefix up to and
    including the trailing colon, e.g. `arn:aws:sns:us-east-1:123456789012:`
  - `EVENT_BROKER_AWS_SNS_ENDPOINT_URL` — override for LocalStack / staging
    only. Leave unset to hit real AWS.
  """

  @behaviour EdgeAdmin.EventBroker.Adapter

  use GenServer

  alias EdgeAdmin.EventBroker.Adapter

  require Logger

  # ---------------------------------------------------------------------------
  # Supervision
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Adapter callbacks
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

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
    case ExAws.request(ExAws.SNS.list_topics()) do
      {:ok, _} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, "SNS unreachable: #{inspect(reason)}"}, state}
    end
  end

  def handle_call({:publish, envelope}, _from, state) do
    topic_arn = state.topic_arn_prefix <> topic_suffix_for(envelope["type"])
    payload = Jason.encode!(envelope)

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

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp topic_suffix_for("edge.node." <> _), do: "edge-nodes-events"
  defp topic_suffix_for("edge.enrollment_key." <> _), do: "edge-nodes-events"
  defp topic_suffix_for("edge.command_execution." <> _), do: "edge-commands-events"
  defp topic_suffix_for("edge.self_update_request." <> _), do: "edge-self-updates-events"
  defp topic_suffix_for("edge.ssh_username." <> _), do: "edge-ssh-events"
end
