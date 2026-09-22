# edge_admin/lib/edge_admin/events/broker/adapters/google_pubsub.ex
defmodule EdgeAdmin.Events.Broker.Adapters.GooglePubsub do
  @moduledoc """
  Google Cloud Pub/Sub adapter for the event broker.

  Publishes CloudEvents through the Pub/Sub REST API. Event type and core name
  are sent as message attributes for subscription filtering; the body remains
  the complete CloudEvents envelope. Topics and credentials are deployment
  responsibilities.

  ## Wire format

  The Pub/Sub REST API requires the `data` field to be base64-encoded — that's
  the wire-level contract, not an adapter choice. Subscribers receive the
  same bytes; client libraries auto-decode for them.

  ## Durability

  Pub/Sub buffers messages per subscription (default 7-day retention, max 31)
  until the subscriber ACKs them. This is more like SNS+SQS combined than pure
  SNS — durability is built in once a subscription exists. If no subscription
  exists when Edge Core publishes, the message is dropped (same as SNS without
  subscribers).

  Authentication uses the configured GCP credential provider. Project, topic
  naming, endpoint, and authentication mode come from deployment configuration.
  """

  @behaviour EdgeAdmin.Events.Broker.Adapter

  use GenServer

  alias EdgeAdmin.Events.Broker.Adapter
  alias EdgeAdmin.Events.Broker.TopicRouting

  require Logger

  @goth_name __MODULE__.Goth

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

  @doc """
  Returns the registered Goth process name. The supervisor reads this when
  building children so it can start `{Goth, name: goth_name()}` only when
  `auth: :goth` is configured.
  """
  def goth_name, do: @goth_name

  @impl Adapter
  def healthy? do
    case GenServer.call(__MODULE__, :healthy?) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "Google Pub/Sub adapter not started"}
  end

  @impl Adapter
  def publish(envelope) do
    GenServer.call(__MODULE__, {:publish, envelope})
  rescue
    _ -> {:error, "Google Pub/Sub adapter not started"}
  end

  @impl GenServer
  def init([]) do
    config = Application.get_env(:edge_admin, :event_broker_google_pubsub, [])

    state = %{
      project: Keyword.fetch!(config, :project),
      topic_id_prefix: Keyword.get(config, :topic_id_prefix, ""),
      base_url: Keyword.fetch!(config, :base_url),
      auth: Keyword.fetch!(config, :auth)
    }

    Logger.info(
      "[EventBroker.GooglePubsub] Configured for project=#{state.project} " <>
        "base_url=#{state.base_url} auth=#{state.auth}"
    )

    {:ok, state}
  end

  # Health probe: GET on the node-events topic resource. Validates auth +
  # network + that the topic actually exists (more meaningful than ListTopics).
  @impl GenServer
  def handle_call(:healthy?, _from, state) do
    url = topic_url(state, "edge-nodes-events")

    case Req.get(url, headers: auth_headers(state.auth)) do
      {:ok, %{status: 200}} ->
        {:reply, :ok, state}

      {:ok, %{status: status, body: body}} ->
        {:reply, {:error, "Pub/Sub healthcheck status=#{status}: #{inspect(body)}"}, state}

      {:error, reason} ->
        {:reply, {:error, "Pub/Sub unreachable: #{inspect(reason)}"}, state}
    end
  end

  def handle_call({:publish, envelope}, _from, state) do
    url = topic_url(state, TopicRouting.topic_for(envelope["type"])) <> ":publish"

    body = %{
      "messages" => [
        %{
          # Pub/Sub REST API requires `data` to be base64-encoded — wire format,
          # not an adapter choice. Subscribers receive the same bytes back.
          "data" => Base.encode64(JSON.encode!(envelope)),
          "attributes" => %{
            "type" => envelope["type"],
            "corename" => envelope["corename"]
          }
        }
      ]
    }

    case Req.post(url, headers: auth_headers(state.auth), json: body) do
      {:ok, %{status: 200}} -> {:reply, :ok, state}
      {:ok, %{status: status, body: response}} -> {:reply, {:error, "status=#{status}: #{inspect(response)}"}, state}
      {:error, reason} -> {:reply, {:error, inspect(reason)}, state}
    end
  end

  defp topic_url(state, topic_id) do
    "#{state.base_url}/v1/projects/#{state.project}/topics/#{state.topic_id_prefix}#{topic_id}"
  end

  defp auth_headers(:none), do: []

  defp auth_headers(:goth) do
    case Goth.fetch(@goth_name) do
      {:ok, %{token: token}} -> [{"authorization", "Bearer #{token}"}]
      {:error, reason} -> raise "Goth token fetch failed: #{inspect(reason)}"
    end
  end
end
